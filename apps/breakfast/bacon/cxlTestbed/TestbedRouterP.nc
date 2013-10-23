
 #include "testbed.h"
 #include "TestbedDebug.h"
module TestbedRouterP{
  uses interface CXDownload;
  uses interface DownloadNotify;
  uses interface AMSend;
  uses interface Receive;
  uses interface Pool<message_t>;
  uses interface CXLinkPacket;
} implementation {
  message_t* testMsg = NULL;
  uint16_t packetsQueued = 0;

  event message_t* Receive.receive(message_t* msg, void* payload,
      uint8_t len){
    packetsQueued ++;
    return msg;
  }

  task void sendAgain(){
    if (!testMsg){
      if (packetsQueued){
        testMsg = call Pool.get();
        if (!testMsg){
          cerror(TESTBED, "Router Pool Empty\r\n");
        }else{
          error_t error;
          (call CXLinkPacket.getLinkMetadata(testMsg))->dataPending = (packetsQueued > 1);
          error = call AMSend.send(TEST_DESTINATION, testMsg,
            TEST_PAYLOAD_LEN);
           if (SUCCESS != error){
             cerror(TESTBED, "Send %x\r\n", error);
            }
        }
      }
    }
  }

  event void AMSend.sendDone(message_t* msg, error_t error){
    if (error == SUCCESS){
      if (packetsQueued){
        packetsQueued --;
      }
    }
    call Pool.put(msg);
    testMsg = NULL;
    post sendAgain();
  }

  event void DownloadNotify.downloadStarted(){
    packetsQueued += PACKETS_PER_DOWNLOAD;
    post sendAgain();
  }

  task void startDownload(){
    error_t error = call CXDownload.startDownload();
    if (error != SUCCESS){
      cerror(TESTBED, "DOWNLOAD %x\r\n", error);
    }
  }

  event void DownloadNotify.downloadFinished(){
    post startDownload();
  }
  event void CXDownload.downloadFinished(){}

}
