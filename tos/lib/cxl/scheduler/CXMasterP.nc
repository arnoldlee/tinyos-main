
 #include "CXRouter.h"
 #include "CXRouterDebug.h"
module CXMasterP {
  provides interface SlotController;
  provides interface CXDownload[uint8_t ns];

  uses interface LppControl;
  uses interface Neighborhood;
  uses interface ActiveMessageAddress;
  provides interface CTS[uint8_t ns];
  provides interface Receive;

  uses interface Get<probe_schedule_t*> as GetProbeSchedule;
  provides interface Get<am_addr_t> as GetRoot[uint8_t ns];

  uses interface SettingsStorage;
} implementation {

  contact_entry_t contactList[CX_MAX_SUBNETWORK_SIZE];
  uint8_t contactIndex;
  uint8_t numRounds;
  uint8_t totalNodes;
  uint8_t activeNS = NS_INVALID;
  uint8_t maxRounds = DEFAULT_MAX_DOWNLOAD_ROUNDS;

  am_addr_t masters[NUM_SEGMENTS] = {AM_BROADCAST_ADDR, 
                                     AM_BROADCAST_ADDR, 
                                     AM_BROADCAST_ADDR};

  command am_addr_t GetRoot.get[uint8_t ns](){
    return masters[ns];
  }

  command error_t CXDownload.startDownload[uint8_t ns](){
    if (ns != NS_ROUTER && ns != NS_SUBNETWORK && ns != NS_GLOBAL){
      return EINVAL;
    }
    if (activeNS != NS_INVALID){
      return EBUSY;
    }else if ((call GetProbeSchedule.get())->invFrequency[ns] == 0){
      return EINVAL;
    } else {
      error_t error = call LppControl.wakeup(ns);
      if (error == SUCCESS){
        call SettingsStorage.get(SS_KEY_MAX_DOWNLOAD_ROUNDS,
          &maxRounds, sizeof(maxRounds));
        //Initialization
        // - Put self in contact list, set totalNodes to 1 (just self)
        // - set self DP to true
        // - point to start of list
        // - clear num rounds counter
        memset(contactList, sizeof(contactList), 0xFF);
        contactList[0].nodeId = call ActiveMessageAddress.amAddress();
        contactList[0].dataPending = TRUE;
        contactIndex = 0;
        totalNodes = 1;
        numRounds = 0;
      }
      return error;
    }
  }

  task void downloadFinished(){
    cinfo(ROUTER, "Download finished\r\n");
    signal CXDownload.downloadFinished[activeNS]();
  }

  command bool SlotController.isActive(){
    //Loop through contact list (wrapping contactIndex at totalNodes) until you either:
    // - hit a node with pending data
    // - complete the maxRounds-th loop of the entire list
    while (numRounds < maxRounds && !contactList[contactIndex].dataPending){
      contactIndex++;
      if (contactIndex >= totalNodes){
        contactIndex = contactIndex % totalNodes;
        numRounds++;
      }
    }
    //If the above loop did not put you over the maxRounds limit, then
    // we're pointing at a node with pending data. go go go
    if (numRounds < maxRounds){
      return TRUE;
    }else {
      //If we did exceed the limit, then we're done, and contactIndex
      //  is pointing at a node with pending data.
      post downloadFinished();
      return FALSE;
    }
  }
  
  //Since the above isActive loop leaves us pointing at a node with
  //  pending data, just return the node at contactIndex.
  command am_addr_t SlotController.activeNode(){
    return contactList[contactIndex].nodeId;
  }
  
  //If we get a status message from the active node (potentially
  //  ourself):
  // - Update dataPending for this node
  // - add any newly-discovered neighbors to the list and increment
  //   totalNodes to reflect them.
  command message_t* SlotController.receiveStatus(message_t* msg,
      cx_status_t* pl){
    //Can this be moved into a task? might be kind of slow.
    uint8_t i;
    uint8_t k;
    contactList[contactIndex].dataPending = pl->dataPending;
    cdbg(ROUTER, "rs %u %u\r\n", 
      contactList[contactIndex].nodeId,
      contactList[contactIndex].dataPending);
    for (i = 0; i < CX_NEIGHBORHOOD_SIZE; i++){
      if (pl->neighbors[i] != AM_BROADCAST_ADDR){
        bool found = FALSE;
        for (k = 0; k < totalNodes && !found; k++){
          if (contactList[k].nodeId == pl->neighbors[i]){
            found = TRUE;
          }
        }
        if (! found){
          if (totalNodes < CX_MAX_SUBNETWORK_SIZE){
            contactList[totalNodes].nodeId = pl->neighbors[i];
            contactList[totalNodes].dataPending = TRUE;
            cdbg(ROUTER, "Add %x at %u\r\n",
              pl->neighbors[i], 
              totalNodes);
            totalNodes ++;
          }else {
            cwarn(ROUTER, 
              "No space to add %x to contact list\r\n",
              pl->neighbors[i]);
          }
        }
      }
    }
    return signal Receive.receive(msg, pl, sizeof(cx_status_t));
  }
  
  //If we get an EOS message from the active node (potentially
  //  ourself):
  // - update dataPending for the node.
  command message_t* SlotController.receiveEOS(message_t* msg,
      cx_eos_t* pl){
    contactList[contactIndex].dataPending = pl->dataPending;
    cdbg(ROUTER, "node %u pending %u\r\n",
      contactList[contactIndex].nodeId,
      contactList[contactIndex].dataPending);
    return msg;
  }
  
  //At the end of a slot, increment contactIndex, wrap if needed.
  command void SlotController.endSlot(){
    contactIndex++;
    if (contactIndex >= totalNodes){
      contactIndex = contactIndex % totalNodes;
      numRounds++;
    }
  }

  default event message_t* Receive.receive(message_t* msg, void* pl,
      uint8_t len){
    return msg;
  }

  command bool SlotController.isMaster(){
    return TRUE;
  }

  command uint8_t SlotController.bw(uint8_t ns){
    probe_schedule_t* sched = call GetProbeSchedule.get();
    return sched->bw[ns];
  }

  command uint8_t SlotController.maxDepth(uint8_t ns){
    probe_schedule_t* sched = call GetProbeSchedule.get();
    return sched->maxDepth[ns];
  }

  command uint32_t SlotController.wakeupLen(uint8_t ns){
    probe_schedule_t* sched = call GetProbeSchedule.get();
    return ((sched->invFrequency[ns]*(sched->probeInterval)) << 5) * call SlotController.maxDepth(ns);
  }


  command void SlotController.receiveCTS(am_addr_t master, uint8_t ns){
    masters[ns] = master;
    signal CTS.ctsReceived[ns]();
  }

  async event void ActiveMessageAddress.changed(){}
  
  event void LppControl.fellAsleep(){
    activeNS = NS_INVALID;
  }

  event void LppControl.wokenUp(uint8_t ns){
    activeNS = ns;
  }

  default event void CTS.ctsReceived[uint8_t ns](){}
  default event void CXDownload.downloadFinished[uint8_t ns](){}


  
}
