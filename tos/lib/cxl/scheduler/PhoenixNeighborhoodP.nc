
 #include "phoenix.h"
 #include "phoenixDebug.h"
 #include "multiNetwork.h"
 #include "CXMac.h"
module PhoenixNeighborhoodP {
  uses interface Timer<TMilli>;
  uses interface SettingsStorage;
  uses interface LogWrite;
  uses interface LppProbeSniffer as SubLppProbeSniffer;
  provides interface LppProbeSniffer;
  uses interface Boot;
  uses interface CXLinkPacket;
  uses interface Packet;
  uses interface Get<uint16_t> as RebootCounter;
} implementation {
  phoenix_reference_t ref;

  void setNext(){
    uint32_t sampleInterval = DEFAULT_PHOENIX_SAMPLE_INTERVAL;
    call SettingsStorage.get(SS_KEY_PHOENIX_SAMPLE_INTERVAL, 
      &sampleInterval, sizeof(sampleInterval));
    cdbg(PHOENIX, "set next: %lu default %lu\r\n",
      sampleInterval, DEFAULT_PHOENIX_SAMPLE_INTERVAL);

    //TODO: might be worth randomizing this, at least on the testbed.
    call Timer.startOneShot(sampleInterval);
  }

  event void Boot.booted(){
    ref.recordType = RECORD_TYPE_PHOENIX;
    setNext();
  }
  
  uint8_t refsCollected;
  uint8_t totalChecks;
  uint8_t targetRefs = DEFAULT_PHOENIX_TARGET_REFS;
  am_addr_t lastSrc;

  task void sniffAgain(){
    error_t error = call SubLppProbeSniffer.sniff(NS_SUBNETWORK);
    cdbg(PHOENIX, "sniff: %x\r\n", error);
    if (error == SUCCESS){
      //cool. wait until we get a sniffDone.
    } else {
      setNext();
    }
  }

  event void Timer.fired(){
    cdbg(PHOENIX, "phoenix start\r\n");
    refsCollected = 0;
    totalChecks = 0;
    lastSrc = AM_BROADCAST_ADDR;
    call SettingsStorage.get(SS_KEY_PHOENIX_TARGET_REFS, 
      &targetRefs, sizeof(targetRefs));
    post sniffAgain();
  }
  
  bool appending = FALSE;
  task void logReference(){
    cdbg(PHOENIX, "Logging (%x, (%u, %lu), (%u, %lu))\r\n",
      ref.node2, ref.rc1, ref.localTime1, ref.rc2, ref.localTime2);
    if ( call LogWrite.append(&ref, sizeof(ref)) == SUCCESS){
      appending = TRUE;
    }
  }

  event void LogWrite.appendDone(void* buf, storage_len_t len, 
      bool recordsLost, error_t error){
    appending = FALSE;
  }

//  uint32_t toMilli(uint32_t t32k){
//    uint32_t milli = call Timer.getNow()
//    //if msb(32k) is set, but corresponding bit in milli is clear,
//    //then 32k time has rolled over between ts assignment and now.
//    if ( (t32k & (1UL << 31)) & ((t32k & (1UL << 31) ) ^ ((milli << 5) & (1UL << 31)))){ 
//      milli -= (1UL << 27);
//    }  
//    return (milli & ((BIT1|BIT2|BIT3|BIT4|BIT5) << 27)) | (t32k >> 5);
//  }

  event message_t* SubLppProbeSniffer.sniffProbe(message_t* msg){
    refsCollected++;
    cdbg(PHOENIX, "probe from %x\r\n", call CXLinkPacket.source(msg) );
    if (! appending && call CXLinkPacket.source(msg) != lastSrc){
      cx_lpp_probe_t* pl = call Packet.getPayload(msg,
        sizeof(cx_lpp_probe_t));
      lastSrc = call CXLinkPacket.source(msg);
      ref.node2 = lastSrc;
      ref.rc2 = pl->rc;
      ref.localTime2 = pl->tMilli;
      ref.rc1 = call RebootCounter.get();
      ref.localTime1 = (call CXLinkPacket.getLinkMetadata(msg))->timeMilli;
      post logReference();
    }
    return signal LppProbeSniffer.sniffProbe(msg);
  }

  command error_t LppProbeSniffer.sniff(uint8_t ns){
    return FAIL;
  }

  event void SubLppProbeSniffer.sniffDone(error_t error){
    totalChecks++;
    cdbg(PHOENIX, "sniff done %u %u %u %u\r\n", 
      refsCollected, targetRefs, totalChecks, MAX_WASTED_SNIFFS);
    if (refsCollected < targetRefs && totalChecks < targetRefs + MAX_WASTED_SNIFFS){
      post sniffAgain();
    }else{
      setNext();
    }
  }

  event void LogWrite.syncDone(error_t error){ }
  event void LogWrite.eraseDone(error_t error){ }
}