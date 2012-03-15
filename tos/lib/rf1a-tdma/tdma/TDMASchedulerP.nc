
 #include "schedule.h"
 #include "stateSafety.h"
module TDMASchedulerP{
  provides interface SplitControl;
  provides interface CXTDMA;
  provides interface TDMAScheduler;
  provides interface TDMARootControl;

  uses interface SplitControl as SubSplitControl;
  uses interface CXTDMA as SubCXTDMA;

  uses interface AMPacket; 
  uses interface CXPacket; 
  uses interface Packet; 
  uses interface Rf1aPacket; 
  uses interface Ieee154Packet;
} implementation {
  enum{
    ERROR_MASK = 0x80,
    S_ERROR_1 = 0x81,
    S_ERROR_2 = 0x82,
    S_ERROR_3 = 0x83,
    S_ERROR_4 = 0x84,
    S_ERROR_5 = 0x85,
    S_ERROR_6 = 0x86,
    S_ERROR_7 = 0x87,
    S_ERROR_8 = 0x88,
    S_ERROR_9 = 0x89,
    S_ERROR_a = 0x8a,
    S_ERROR_b = 0x8b,
    S_ERROR_c = 0x8c,
    S_ERROR_d = 0x8d,
    S_ERROR_e = 0x8e,
    S_ERROR_f = 0x8f,

    S_OFF = 0x00,
    S_STARTING = 0x01,
    S_STOPPING = 0x02,

    S_R_UNSCHEDULED = 0x10,
    S_R_RUNNING = 0x11,

    S_NR_UNSCHEDULED = 0x20,
    S_NR_RUNNING     = 0x21,
  };

  uint8_t state = S_OFF;
  //macro for state-safety
  SET_STATE_DEF

  message_t schedule_msg_internal;
  message_t* schedule_msg = &schedule_msg_internal;
  cx_schedule_t* schedule_pl;

  //this should be constant once written the first time.
  norace uint8_t schedule_len;

  bool updatePending = FALSE;
  //protected by updatePending
  norace uint32_t lastFs;
  norace cx_schedule_t lastSchedule;

  void setupPacket(uint32_t frameLen, uint32_t fwCheckLen, uint16_t activeFrames, uint16_t inactiveFrames, uint16_t framesPerSlot, uint8_t maxRetransmit){
    call CXPacket.init(schedule_msg);

    call AMPacket.setDestination(schedule_msg, AM_BROADCAST_ADDR);
    call CXPacket.setDestination(schedule_msg, AM_BROADCAST_ADDR);
    call CXPacket.setType(schedule_msg, CX_TYPE_SCHEDULE);
    if (schedule_pl == NULL){
      schedule_pl = (cx_schedule_t*)call Packet.getPayload(schedule_msg, sizeof(cx_schedule_t));
      schedule_len = sizeof(cx_schedule_t) + ((uint16_t)schedule_pl - (uint16_t)schedule_msg);
    }
    schedule_pl -> rootStart = 0;
    schedule_pl -> originalFrame = 0;
    schedule_pl -> frameLen = frameLen;
    schedule_pl -> activeFrames = activeFrames;
    schedule_pl -> inactiveFrames = inactiveFrames;
    schedule_pl -> framesPerSlot = framesPerSlot;
    schedule_pl -> maxRetransmit = maxRetransmit;
    printf("s_len: %u\r\n", schedule_len);
  }

  command error_t SplitControl.start(){
    error_t error;
    TMP_STATE;
    CACHE_STATE;
    error = call SubSplitControl.start();
    if (SUCCESS == error){
      SET_STATE(S_STARTING, S_ERROR_1);
    } else {
      SET_ESTATE(S_ERROR_1);
    }
    return error;
  }

  command error_t SplitControl.stop(){
    return call SubSplitControl.stop();
  }

  task void nrSetup(){
    error_t error;
    TMP_STATE;
    CACHE_STATE;
    error = call SubCXTDMA.setSchedule(
      call SubCXTDMA.getNow(), 
      0,
      DEFAULT_TDMA_FRAME_LEN,
      2*DEFAULT_TDMA_FRAME_LEN,
      1, 0);
    if (SUCCESS == error){
      SET_STATE(S_NR_UNSCHEDULED, S_ERROR_2);
    }
  }

  event void SubSplitControl.startDone(error_t error){
    TMP_STATE;
    CACHE_STATE;
    if (SUCCESS == error){
      if (signal TDMARootControl.isRoot()){
        if ( SET_STATE(S_R_UNSCHEDULED, S_ERROR_3)){
          signal SplitControl.startDone(SUCCESS);
        } else {
          signal SplitControl.startDone(FAIL);
        }
      } else {
        post nrSetup();
      }
    }else{
      SET_ESTATE(S_ERROR_3);
      signal SplitControl.startDone(error);
    }
  }

  event void SubSplitControl.stopDone(error_t error){
    TMP_STATE;
    CACHE_STATE;
    if (SUCCESS == error){
      SET_STATE(S_OFF, S_ERROR_4);
    } else {
      SET_ESTATE(S_ERROR_4);
    }
    signal SplitControl.stopDone(error);
  }

  //calls should go through the TDMAScheduler interface.
  command error_t CXTDMA.setSchedule(uint32_t startAt,
      uint16_t atFrameNum, uint32_t frameLen, 
      uint32_t fwCheckLen, uint16_t activeFrames, 
      uint16_t inactiveFrames){
    return FAIL;
  }

  command error_t TDMARootControl.setSchedule(uint32_t frameLen, 
      uint32_t fwCheckLen, uint16_t activeFrames, 
      uint16_t inactiveFrames, uint16_t framesPerSlot, 
      uint16_t maxRetransmit){
    TMP_STATE;
    CACHE_STATE;
    if (CHECK_STATE(S_R_UNSCHEDULED) || CHECK_STATE(S_R_RUNNING)){
      error_t error = call SubCXTDMA.setSchedule(
        call SubCXTDMA.getNow(), 0, frameLen, fwCheckLen, activeFrames, inactiveFrames);

      if (SUCCESS == error){
        setupPacket(frameLen, fwCheckLen, activeFrames,
          inactiveFrames, framesPerSlot, maxRetransmit);
        SET_STATE(S_R_RUNNING, S_ERROR_5);
      } else {
        SET_ESTATE(S_ERROR_5);
      }
      return error;
    } else{
      return FAIL;
    }
  }

  async command uint32_t CXTDMA.getNow(){
    return call SubCXTDMA.getNow();
  }

  /**
   *  Root broadcasts during frame 0. All other behavior is up to
   *  higher levels.
   *
   */
  async event rf1a_offmode_t SubCXTDMA.frameType(uint16_t frameNum){
    if ((state == S_R_RUNNING) && (frameNum == 0)){
      return RF1A_OM_FSTXON;
    } else if (state == S_NR_UNSCHEDULED){
      return RF1A_OM_RX;
    } else {
      return signal CXTDMA.frameType(frameNum);
    }
  }

  async event bool SubCXTDMA.getPacket(message_t** msg, uint8_t* len,
      uint16_t frameNum){
    //root broadcasts during frame 0. Everything else is up to higher
    //  levels (including retransmitting this, etc.)
    if ((state == S_R_RUNNING) && (frameNum == 0)){
      *msg = schedule_msg;
      *len = schedule_len;
      return TRUE;
    } else {
      return signal CXTDMA.getPacket(msg, len, frameNum);
    }
  }

  task void signalScheduled(){
    TMP_STATE;
    CACHE_STATE;
    if (CHECK_STATE(S_R_RUNNING)){
      call CXPacket.newSn(schedule_msg);
    }
    if (schedule_pl != NULL){
      signal TDMAScheduler.scheduleReceived(schedule_pl->activeFrames,
        schedule_pl->inactiveFrames, schedule_pl->framesPerSlot,
        schedule_pl->maxRetransmit);
    } else {
      SET_ESTATE(S_ERROR_8);
    }
  }

  async event void SubCXTDMA.sendDone(message_t* msg, uint8_t len,
      uint16_t frameNum, error_t error){
    if ((state == S_R_RUNNING) && (frameNum == 0)){
      post signalScheduled();
    } else {
      signal CXTDMA.sendDone(msg, len, frameNum, error);
    }
  }
 

  task void processReceive(){
    TMP_STATE;
    error_t error;
    CACHE_STATE;
    error = call SubCXTDMA.setSchedule(lastFs, 
      lastSchedule.originalFrame,
      lastSchedule.frameLen, 
      DEFAULT_TDMA_FW_CHECK_LEN,
      lastSchedule.activeFrames,
      lastSchedule.inactiveFrames);
    atomic updatePending = FALSE;
    if (SUCCESS != error){
      printf("Error %s\r\n", decodeError(error));
      SET_ESTATE(S_ERROR_6);
    } else {
      if (CHECK_STATE(S_NR_UNSCHEDULED)){
//        printf("scheduled\r\n");
        SET_STATE(S_NR_RUNNING, S_ERROR_6);
        signal SplitControl.startDone(SUCCESS);
      } else {
//        printf("updated\r\n");
      }
      signal TDMAScheduler.scheduleReceived(lastSchedule.activeFrames,
        lastSchedule.inactiveFrames, lastSchedule.framesPerSlot,
        lastSchedule.maxRetransmit);
    }
  }

  async event message_t* SubCXTDMA.receive(message_t* msg, 
      uint8_t len, uint16_t frameNum){
    //if we're in need of a schedule, grab it now before signalling
    //this up to the upper layers (which may lay claim to this
    //buffer).
//    printf("s %x f %u t %x\r\n", state, frameNum, 
//      call CXPacket.type(msg));
    if ((state == S_NR_UNSCHEDULED) || 
         ((state == S_NR_RUNNING) 
           && (frameNum == 0) 
           && (call CXPacket.type(msg) == CX_TYPE_SCHEDULE))){
      cx_schedule_t* pl;
      bool okToProceed = TRUE;

      atomic {
        if (!updatePending){
          updatePending = TRUE;
        //still haven't handled previous update.
        } else{
          okToProceed = FALSE;
        }
      }
      if (okToProceed){
        pl = (cx_schedule_t*)call Packet.getPayload(msg, len);
  //      printf("RX schedule\r\n");
  //      lastSchedule.rootStart = pl->rootStart;
        lastSchedule.originalFrame = 
          call CXPacket.count(msg) + pl->originalFrame;
        lastSchedule.frameLen = pl->frameLen;
        lastSchedule.activeFrames = pl->activeFrames;
        lastSchedule.inactiveFrames = pl->inactiveFrames;
        lastSchedule.framesPerSlot = pl->framesPerSlot;
        lastSchedule.maxRetransmit = pl->maxRetransmit;
        post processReceive();
      }
    }else{
      //this layer doesn't care what it is.
//      return msg;
    }
    //TODO: only signal up if we are in a synched state?
    return signal CXTDMA.receive(msg, len, frameNum);
  }

  async event void SubCXTDMA.frameStarted(uint32_t startTime){
////If the physical layer was actually fully interrupt-driven, then we could
////fill in the SFD time of the transmitter at the end of the packet.
////But, it's not, so it's already in the TXFIFO. boo.
//    if ( state == S_R_RUNNING  && frameNum == 0){
//      cx_schedule_t* pl = 
//        (cx_schedule_t*)call Packet.getPayload(schedule_msg, sizeof(cx_schedule_t));
//     pl -> rootTime = startTime
//    }
    if (!updatePending){
      lastFs = startTime;
    } else {
      SET_ESTATE(S_ERROR_8);
    }
    signal CXTDMA.frameStarted(startTime);
    //TODO: add another event that indicates "we're inactive now"?
  }

}
