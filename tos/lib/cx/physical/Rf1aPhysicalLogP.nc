module Rf1aPhysicalLogP {
  uses interface Rf1aPhysical as SubRf1aPhysical;
  provides interface DelayedSend;
  uses interface DelayedSend as SubDelayedSend;
  provides interface Rf1aPhysical;
  provides interface RadioStateLog;
  uses interface LocalTime<T32khz>;
} implementation {

  enum{
    R_OFF = 0,
    R_SLEEP = 1,
    R_IDLE = 2, 
    R_FSTXON = 3,
    R_TX = 4,
    R_RX = 5,
    R_NUMSTATES = 6
  };

  const char labels[R_NUMSTATES] = {'o', 's', 'i', 'f', 't', 'r'};
  uint8_t  curRadioState = R_OFF;
  uint32_t lastRadioStateChange;
  uint32_t radioStateTimes[R_NUMSTATES];
  uint32_t logBatch;
  
  void radioStateChange(uint8_t newState){
    atomic{
      uint32_t changeTime = call LocalTime.get();
      if (newState != curRadioState){
        uint32_t elapsed = changeTime-lastRadioStateChange;
        radioStateTimes[curRadioState] += elapsed;
        curRadioState = newState;
        lastRadioStateChange = changeTime;
      }
    }
  }

  uint32_t rst[R_NUMSTATES];
  
  bool logging = FALSE;
  uint8_t dc_i;

  task void logNextStat(){
    if (dc_i < R_NUMSTATES){
      cinfo(RADIOSTATS, "RS %lu %c %lu\r\n", 
        logBatch, labels[dc_i], rst[dc_i]);
      dc_i ++;
      post logNextStat();
    }else{
      logging = FALSE;
    }
  }

  command error_t RadioStateLog.dump(uint32_t lb){
    if (!logging){
      atomic{
        uint8_t k;
        for (k = 0; k < R_NUMSTATES; k++){
          rst[k] = radioStateTimes[k];
        }
      }
      logBatch = lb;
      dc_i = 0;
      logging = TRUE;
      post logNextStat();
      return SUCCESS;
    }else {
      return EBUSY;
    }
  }
  
  command error_t Rf1aPhysical.send (uint8_t* buffer, 
      unsigned int length, rf1a_offmode_t offMode){
    //no state change: controlled by startTransmission.
    return call SubRf1aPhysical.send(buffer, length, offMode);
  }

  async event void SubRf1aPhysical.sendDone (int result){
    radioStateChange(R_IDLE);
    signal Rf1aPhysical.sendDone(result);
  }

  async command error_t Rf1aPhysical.startTransmission (bool check_cca, bool targetFSTXON){
    error_t ret = call SubRf1aPhysical.startTransmission(check_cca, targetFSTXON);
    if (ret == SUCCESS){
      if (targetFSTXON){
        radioStateChange(R_FSTXON);
      }else{
        radioStateChange(R_TX);
      }
    }
    return ret;
  }

  async command error_t Rf1aPhysical.startReception (){
    //unused
    return call SubRf1aPhysical.startReception();
  }

  async command error_t Rf1aPhysical.resumeIdleMode (bool rx ){
    error_t ret = call SubRf1aPhysical.resumeIdleMode(rx);
    if (ret == SUCCESS){
      if (rx){
        radioStateChange(R_RX);
      }else{
        radioStateChange(R_IDLE);
      }
    }
    return ret;
  }

  async command error_t Rf1aPhysical.sleep (){
    error_t ret = call SubRf1aPhysical.sleep();
    if (ret == SUCCESS){
      radioStateChange(R_SLEEP);
    }
    return ret;
  }

  async event void SubRf1aPhysical.receiveStarted (unsigned int length){
    signal Rf1aPhysical.receiveStarted(length);
  }
  async event void SubRf1aPhysical.receiveDone (uint8_t* buffer,
                                unsigned int count,
                                int result){
    radioStateChange(R_IDLE);
    signal Rf1aPhysical.receiveDone(buffer, count, result);
  }
  async command error_t Rf1aPhysical.setReceiveBuffer (uint8_t* buffer,
                                          unsigned int length,
                                          bool single_use){
    error_t ret = call SubRf1aPhysical.setReceiveBuffer(buffer, length,
      single_use);
    if (ret == SUCCESS){
      radioStateChange(R_RX);
    }
    return ret;
  }

  async event void SubRf1aPhysical.receiveBufferFilled (uint8_t* buffer,
                                        unsigned int count){
    signal Rf1aPhysical.receiveBufferFilled(buffer, count);
  }
  async event void SubRf1aPhysical.frameStarted (){
    signal Rf1aPhysical.frameStarted();
  }
  async event void SubRf1aPhysical.clearChannel (){
    signal Rf1aPhysical.clearChannel();
  }
  
  event void SubDelayedSend.sendReady(){
    signal DelayedSend.sendReady();
  }

  async command error_t DelayedSend.startSend(){
    
    error_t ret = call SubDelayedSend.startSend();
    if (ret == SUCCESS){
      radioStateChange(R_TX);
    }
    return ret;
  }

  async command void Rf1aPhysical.readConfiguration (rf1a_config_t* config){
    call SubRf1aPhysical.readConfiguration(config);
  }

  async command void Rf1aPhysical.reconfigure(){
    return call SubRf1aPhysical.reconfigure();
  }

  async command int Rf1aPhysical.enableCca(){
    return call SubRf1aPhysical.enableCca();
  }

  async command int Rf1aPhysical.disableCca(){
    return call SubRf1aPhysical.disableCca();
  }

  async command int Rf1aPhysical.rssi_dBm (){
    return call SubRf1aPhysical.rssi_dBm();
  }

  async command int Rf1aPhysical.setChannel (uint8_t channel){
    return call SubRf1aPhysical.setChannel(channel);
  }
  async command int Rf1aPhysical.getChannel (){
    return call SubRf1aPhysical.getChannel();
  }
  async event void SubRf1aPhysical.carrierSense () { 
    signal Rf1aPhysical.carrierSense();
  }
  async event void SubRf1aPhysical.released () { 
    signal Rf1aPhysical.released();
  }
}