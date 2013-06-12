
 #include "CXLink.h"
module CXLinkP {
  provides interface SplitControl;
  uses interface Resource;

  uses interface Rf1aPhysical;
  uses interface DelayedSend;

  uses interface GpioCapture as SynchCapture;
  uses interface Msp430XV2ClockControl;
  uses interface Alarm<TMicro, uint32_t> as FastAlarm;
  uses interface LocalTime<T32khz>; 

  provides interface Receive;
  provides interface Send;
  provides interface CXLink;

  uses interface Pool<message_t>;

  uses interface Packet;
  uses interface CXLinkPacket;

  uses interface Rf1aPhysicalMetadata;
} implementation {
  message_t* rxMsg;
  uint8_t rxLen;
  message_t* fwdMsg;

  enum {
    S_SLEEP = 0,

    S_RX = 1,
    S_TX = 2,
    S_FWD = 3,

    S_IDLE = 7,
  };

  uint8_t state = S_SLEEP;
  uint32_t aSfdCapture;
  bool aCSDetected;
  int32_t sfdAdjust;

  cx_link_header_t* header(message_t* msg){
    return (call CXLinkPacket.getLinkHeader(msg));
  }

  cx_link_metadata_t* metadata(message_t* msg){
    return (call CXLinkPacket.getLinkMetadata(msg));
  }
  
  /**
   *  Immediately sleep the radio. 
   */
  command error_t CXLink.sleep(){
    //TODO: verify that we're not active (either in the process of
    //forwarding or during an active reception event)
    return call Rf1aPhysical.sleep();
  }


  task void handleSendDone();
  bool readyForward(message_t* msg);
  error_t subsend(message_t* msg);

  event void DelayedSend.sendReady(){
    if (aSfdCapture){
      atomic call FastAlarm.startAt(aSfdCapture, FRAMELEN_FAST + sfdAdjust);
    }else{
      call DelayedSend.startSend();
    }
  }

  async event void Rf1aPhysical.sendDone (int result) { 
    atomic sfdAdjust = TX_SFD_ADJUST;
    post handleSendDone();
  }

  task void handleSendDone(){
    uint8_t localState;
    atomic localState = state;
    if (localState == S_TX || localState == S_FWD){
      if (readyForward(fwdMsg)){
        subsend(fwdMsg);
      } else {
        if (localState == S_TX){
          atomic {
            state = S_IDLE;
            call Msp430XV2ClockControl.stopMicroTimer();
            call Rf1aPhysical.resumeIdleMode(RF1A_OM_IDLE);
          }
          signal Send.sendDone(fwdMsg, SUCCESS);
        } else {
          atomic {
            state = S_IDLE;
            call CXLinkPacket.setLen(rxMsg, rxLen);
            call Msp430XV2ClockControl.stopMicroTimer();
            call Rf1aPhysical.resumeIdleMode(RF1A_OM_IDLE);
          }
          rxMsg = signal Receive.receive(rxMsg, 
            call Packet.getPayload(rxMsg, call Packet.payloadLength(rxMsg)), 
            call Packet.payloadLength(rxMsg));
          signal CXLink.rxDone();
        }
      }
    }
  }

  
  task void signalRXDone(){
    signal CXLink.rxDone();
  }

  async event void FastAlarm.fired(){
    if (state == S_FWD){
      call DelayedSend.startSend();
    } else if (state == S_RX){
      if (aCSDetected){
        aCSDetected = FALSE;
        call FastAlarm.start(CX_CS_TIMEOUT_EXTEND);
      } else {
        call Rf1aPhysical.resumeIdleMode(RF1A_OM_IDLE);
        post signalRXDone();
      }
    } else {
      //TODO: handle unexpected state
    }
  }

  async event void SynchCapture.captured(uint16_t time){
    uint32_t ft = call FastAlarm.getNow();
    call FastAlarm.stop();
    if (time > (ft & 0x0000ffff)){
      ft  -= 0x00010000;
    }
    //expand to 32 bits
    aSfdCapture = (ft & 0xffff0000) | time;
    call SynchCapture.disable();
  }

  async event void Rf1aPhysical.receiveStarted(unsigned int length) { 
  }

  async event void Rf1aPhysical.receiveBufferFilled(uint8_t* buffer, unsigned int count) { 
  }


  //--------- RX/TX/FWD flow
  /**
   * Overall:
   * - receive/send switch the radio into the relevant active mode,
   *   offmode = FSTXON, enable synch capture.
   * - at SFD capture, record time of SFD.
   * - Upon reception/completion of send, update the packet headers
   *   and schedule the next forwarding step.
   * - When TTL reaches 0, signal the relevant receive/sendDone event.
   */
  task void handleReception();
  
  /**
   *  Put the radio into RX mode (->FSTXON), and start wait timeout.
   *  Set up SFD capture/etc.
   */
  command error_t CXLink.rx(uint32_t timeout, bool allowForward){
    //switch to data channel if not already on it
    error_t error = call Rf1aPhysical.setReceiveBuffer((uint8_t*)rxMsg, 
      TOSH_DATA_LENGTH + sizeof(message_header_t), TRUE,
      RF1A_OM_FSTXON );
    call Packet.clear(rxMsg);
    metadata(rxMsg)->retx = allowForward;

    if (SUCCESS == error){
      if (! call Msp430XV2ClockControl.isMicroTimerRunning()){
        call Msp430XV2ClockControl.startMicroTimer();
      }
      atomic{
        call FastAlarm.start(timeout);
        call SynchCapture.captureRisingEdge();
        aSfdCapture = 0;
        aCSDetected = FALSE;
        state = S_RX;
      }
    }
    return error;
  }

  /**
   * Set up the radio to transmit the provided packet immediately.
   */
  command error_t Send.send(message_t* msg, uint8_t len){
    aSfdCapture = 0;
    fwdMsg = msg;
    call CXLinkPacket.setLen(msg, len);
    return subsend(msg);
  }
  
  error_t subsend(message_t* msg){
    error_t error;
    if (! call Msp430XV2ClockControl.isMicroTimerRunning()){
      call Msp430XV2ClockControl.startMicroTimer();
    }
    error = call Rf1aPhysical.startTransmission(FALSE, TRUE);
    if (error == SUCCESS) {
      rf1a_offmode_t om = (header(msg)->ttl)?RF1A_OM_FSTXON:RF1A_OM_IDLE;
      call SynchCapture.captureRisingEdge();
      error = call Rf1aPhysical.send((uint8_t*)msg, 
        call CXLinkPacket.len(msg), om);
    }
    return error;
  }

  /**
   * update header fields of packet and return whether or not
   * forwarding is complete.
   */
  bool readyForward(message_t* msg){
    if(header(msg)->ttl){
      header(msg)->hopCount++;
      header(msg)->ttl--;
    }
    return (header(msg)->ttl > 0) && (metadata(rxMsg)->retx);
  }



  async event void Rf1aPhysical.receiveDone (uint8_t* buffer,
                                             unsigned int count,
                                             int result) {
    sfdAdjust = RX_SFD_ADJUST;
    rxLen = count;
    post handleReception();
  } 

  uint32_t fastToSlow(uint32_t fastTicks){
    //OK w.r.t overflow as long as fastTicks is 22 bits or less (0.64 seconds)
    return (FRAMELEN_SLOW*fastTicks)/FRAMELEN_FAST;
  }

  /**
   * Deal with the aftermath of packet reception: record
   * metadata/timing information, prepare for forwarding if needed.
   */
  task void handleReception(){
    uint8_t localState;
    atomic{
      uint32_t fastRef1 = call FastAlarm.getNow();
      uint32_t slowRef = call LocalTime.get();
      uint32_t fastRef2 = call FastAlarm.getNow();
      uint32_t fastTicks = fastRef1 + ((fastRef2-fastRef1)/2) - aSfdCapture - sfdAdjust;
      uint32_t slowTicks = fastToSlow(fastTicks);
      
      call CXLinkPacket.setLen(rxMsg, rxLen);
      metadata(rxMsg)->rxHopCount = header(rxMsg)->hopCount;
      metadata(rxMsg)->rxTime = slowRef 
        - slowTicks 
        - (FRAMELEN_SLOW*(metadata(rxMsg)->rxHopCount-1));
      localState = state;
    }
    if (localState == S_RX){
      if (readyForward(rxMsg) ){
        atomic{
          state = S_FWD;
          fwdMsg = rxMsg;
        }
        subsend(fwdMsg);
      }else{
        atomic {
          state = S_IDLE;
          call Msp430XV2ClockControl.stopMicroTimer();
          call Rf1aPhysical.resumeIdleMode(RF1A_OM_IDLE);
        }
        rxMsg = signal Receive.receive(rxMsg, 
          call Packet.getPayload(rxMsg, call Packet.payloadLength(rxMsg)),
          call Packet.payloadLength(rxMsg));
        signal CXLink.rxDone();
      }
    }else{ 
      //TODO: unexpected state
    }
  }


  command error_t CXLink.txTone(uint8_t channel){
    return FAIL;
  }
  command error_t CXLink.rxTone(uint32_t timeout, uint8_t channel){
    return FAIL;
  }

  //------------
  // "Easy stuff"
  command error_t SplitControl.start(){
    if (call Resource.isOwner()){
      return EALREADY;
    }else{
      return call Resource.request();
    }
  }

  event void Resource.granted(){
    rxMsg = call Pool.get();
    if (rxMsg){
      signal SplitControl.startDone(SUCCESS);
    }else {
      signal SplitControl.startDone(ENOMEM);
    }
  }

  task void signalStopDone(){
    signal SplitControl.stopDone(SUCCESS);
  }

  command error_t SplitControl.stop(){
    if (! call Resource.isOwner()){
      return EALREADY;
    }else{
      post signalStopDone();
      call Pool.put(rxMsg);
      return call Resource.release();
    }
  }

  command void* Send.getPayload(message_t* msg, uint8_t len){
    return call Packet.getPayload(msg, len);
  }

  command uint8_t Send.maxPayloadLength(){
    return call Packet.maxPayloadLength();
  }

  command error_t Send.cancel(message_t* msg){
    return FAIL;
  }

  async event void Rf1aPhysical.frameStarted () { }
  async event void Rf1aPhysical.clearChannel () { }
  async event void Rf1aPhysical.carrierSense () { 
    aCSDetected = TRUE;
  }
  async event void Rf1aPhysical.released () { }

  
}
