module TestP{
  uses interface SplitControl;
  uses interface Boot;
  uses interface Timer<TMilli>;
  uses interface LogWrite;
  provides interface Get<am_addr_t>;
} implementation {
  
  uint8_t testRec[8] = { 8, 7, 6, 5, 4, 3, 2, 1};
  uint8_t curLen = 8;
  
  command am_addr_t Get.get(){
    return AM_BROADCAST_ADDR;
  }

  event void Boot.booted(){
    call SplitControl.start();
  }

  event void SplitControl.startDone(error_t error){
    printf("Booted\n");
    printfflush();
    call Timer.startPeriodic(2048);
  } 

  event void Timer.fired(){
    call LogWrite.append(testRec, curLen);
  }

  event void LogWrite.appendDone(void* buf, storage_len_t len, 
      bool recordsLost, error_t error){ 
    curLen = (curLen == 1)? 8 : curLen-1;
    printf("Append done.\n");
    printfflush();
  }

  event void LogWrite.eraseDone(error_t error){}
  event void LogWrite.syncDone(error_t error){}

  event void SplitControl.stopDone(error_t error){ }
}