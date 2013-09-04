
 #include "AM.h"
 #include "router.h"
 #include "CXRouter.h"
 #include "multiNetwork.h"
module RouterP{
  uses interface Boot;
  uses interface SplitControl;
  uses interface Receive as ReceiveData;
  uses interface AMPacket;

  uses interface Pool<message_t>;
  uses interface LogWrite;

  uses interface Timer<TMilli>;
  uses interface SettingsStorage;
  uses interface CXDownload;
  uses interface Receive as CXDownloadReceive;

} implementation {

  event void Boot.booted(){
    call SplitControl.start();
  }

  task void downloadNext(){
    nx_uint32_t downloadInterval;
    downloadInterval = DEFAULT_DOWNLOAD_INTERVAL;
    call SettingsStorage.get(SS_KEY_DOWNLOAD_INTERVAL,
      &downloadInterval, sizeof(downloadInterval));   
    call Timer.startOneShot(downloadInterval);
  }

  event void SplitControl.startDone(error_t error){
     post downloadNext();
  }

  event void Timer.fired(){
    error_t error = call CXDownload.startDownload();
    cdbg(SCHED, "CXSD %x\r\n", error);
    //getting 6 here
    if (error == ERETRY){
      //This indicates something else was going on (for instance, we
      //were participating in a routers -> BS download) and should be
      //OK to try again momentarily.
      call Timer.startOneShot(DOWNLOAD_RETRY_INTERVAL);
    }else{
      post downloadNext();
    }
  }

  event void CXDownload.downloadFinished(){
    cdbg(SCHED, "DF\r\n");
    post downloadNext();
  }

  event void SplitControl.stopDone(error_t error){
  }
  
  message_t* toAppend;
  void* toAppendPl;
  uint8_t toAppendLen;
  
  //TODO: replace with pool/queue
  tunneled_msg_t tunneled_internal;
  tunneled_msg_t* tunneled = &tunneled_internal;

  task void append(){
    tunneled->recordType = RECORD_TYPE_TUNNELED;
    tunneled->src = call AMPacket.source(toAppend);
    tunneled->amId = call AMPacket.type(toAppend);
    //ugh
    memcpy(tunneled->data, toAppendPl, toAppendLen);
    call LogWrite.append(tunneled, 
      sizeof(tunneled_msg_t));
  }

  event void LogWrite.appendDone(void* buf, storage_len_t len, bool recordsLost, error_t error){
    call Pool.put(toAppend);
    toAppend = NULL;
  }

  event void LogWrite.syncDone(error_t error){}
  event void LogWrite.eraseDone(error_t error){}

  event message_t* ReceiveData.receive(message_t* msg, 
      void* pl, uint8_t len){
    if (toAppend == NULL){
      message_t* ret = call Pool.get();
      if (ret){
        toAppend = msg;
        toAppendPl = pl;
        toAppendLen = len;
        post append();
        return ret;
      }else {
        return msg;
      }
    } else {
      //still handling last packet
      return msg;
    }
  }

  event message_t* CXDownloadReceive.receive(message_t* msg, 
      void* pl, uint8_t len){
    cx_download_t* dpl = (cx_download_t*)pl;
    cdbg(SCHED, "CXDR %u\r\n", dpl->networkSegment);
    if (dpl->networkSegment == NS_SUBNETWORK){
      signal Timer.fired();
    }
    return msg;
  }
}
