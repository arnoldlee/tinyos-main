
 #include "CXScheduler.h"
 #include "CXSchedulerDebug.h"
 #include "CXLink.h"
module CXMasterSchedulerP{
  provides interface SplitControl;
  provides interface CXRequestQueue;
  uses interface Boot;
  uses interface Random;
  
  uses interface SplitControl as SubSplitControl;
  uses interface CXRequestQueue as SubCXRQ;

  uses interface CXSchedulerPacket;
  uses interface Packet;
  uses interface CXPacketMetadata;

  //for addr
  uses interface CXLinkPacket;

  //for TTL
  uses interface CXNetworkPacket;

  uses interface SlotNotify;
  uses interface ScheduleParams;

  uses interface SkewCorrection;

  uses interface ScheduledAMSend as ScheduleSend;
  uses interface ScheduledAMSend as AssignmentSend;
  uses interface RoutingTable;
  uses interface Receive as RequestReceive;
} implementation {
  message_t schedMsg_internal;
  message_t* schedMsg = &schedMsg_internal;
  cx_schedule_t* sched;

  message_t nextMsg_internal;
  message_t* nextMsg = &nextMsg_internal;

  message_t assignMsg_internal;
  message_t* assignMsg = &assignMsg_internal;

  message_t reqMsg_internal;
  message_t* reqMsg = &reqMsg_internal;


  cx_schedule_t* nextSched;
  bool scheduleUpdatePending = FALSE;
  bool startDonePending = FALSE;
  bool scheduleModified = FALSE;

  uint32_t lastSleep = INVALID_FRAME;

  uint32_t lastCycleStart = INVALID_FRAME;

  uint16_t curSlot;//for tracking cycles-since-heard
  bool lastSlotActive = FALSE;
  
  enum {
    SA_OPEN = 0,
    SA_REQUESTED = 1,
    SA_ASSIGNED = 2,
    SA_FREED = 3,
  };

  typedef struct slot_assignment {
    am_addr_t owner;
    uint8_t csh;  //cycles-since-heard
    uint8_t status;
  }slot_assignment_t;

  slot_assignment_t assignments[CX_MAX_SLOTS];

  void fillSchedule(cx_schedule_t* s){
    uint16_t i;
    uint32_t lastActive = 0;
    uint8_t vi=0;
    uint8_t fi=0;
    s->numVacant = 0;

    cdbg(SCHED, "FS:");
    //Fill in the vacantSlots section
    for (i = 0; i < CX_MAX_SLOTS ; i++){
      if (assignments[i].status == SA_OPEN 
          && s->numVacant < MAX_VACANT){
        s->vacantSlots[vi] = i;
        vi++;
        lastActive = i;
        s->numVacant ++;
        cdbg(SCHED, "v %u ", i);
      }else if (assignments[i].status == SA_FREED 
          && fi < MAX_FREED){
        s->freedSlots[fi] = i;
        fi ++;
        cdbg(SCHED, "f %u ", i);
      }
    }
    cdbg(SCHED, "\r\n");

    for (; vi < MAX_VACANT; vi ++){
      s->vacantSlots[vi] = INVALID_SLOT;
    }
    for (; fi < MAX_FREED; fi ++){
      s->freedSlots[fi] = INVALID_SLOT;
    }

    //continue from the last vacant slot to the end, and bump up the
    //# of active slots to cover the entire announced + assigned
    //space.
    for (i=lastActive; i < CX_MAX_SLOTS; i++){
      if(assignments[i].status == SA_ASSIGNED){
        lastActive = i;
      }
    }
    //e.g. if the lastActive slot is 0, there is 1 active slot.
    s->activeSlots = lastActive+1;
  }
  

  task void initializeSchedule(){
    uint8_t i;
    for (i = 1; i < CX_MAX_SLOTS; i++){
      assignments[i].status = SA_OPEN;
      assignments[i].csh = 0;
    }
    assignments[0].owner = TOS_NODE_ID;
    assignments[0].status = SA_ASSIGNED;

    call Packet.clear(schedMsg);
    sched = (cx_schedule_t*)(call ScheduleSend.getPayload(schedMsg,
      sizeof(cx_schedule_t)));
    sched -> sn = call Random.rand16() & 0xFF;
    sched -> cycleLength = CX_DEFAULT_CYCLE_LENGTH;
    sched -> slotLength = CX_DEFAULT_SLOT_LENGTH;
    sched -> maxDepth = CX_DEFAULT_MAX_DEPTH;
    fillSchedule(sched);

    call RoutingTable.setDefault(sched->maxDepth);
  }

  event void Boot.booted(){
    post initializeSchedule();
  }

  void setNextSchedule(uint32_t cycleLength, uint32_t slotLength,
      uint8_t maxDepth){
    call Packet.clear(nextMsg);
    nextSched = call ScheduleSend.getPayload(nextMsg, 
      sizeof(cx_schedule_t));
    nextSched -> sn = sched->sn + 1;
    nextSched -> cycleLength = cycleLength;
    nextSched -> slotLength = slotLength;
    nextSched -> maxDepth = maxDepth;
    fillSchedule(nextSched);
    scheduleUpdatePending = TRUE;
  }

  task void initTask(){
    uint32_t refFrame = call SubCXRQ.nextFrame(FALSE);
    error_t error = call SubCXRQ.requestWakeup(0, refFrame, 1,
      call SkewCorrection.referenceFrame(call CXLinkPacket.addr()),
      call SkewCorrection.referenceTime(call CXLinkPacket.addr()), 
      0);

    if (SUCCESS == error){
      startDonePending = TRUE;
      //cool. we'll request sleep and next wakeup when the wakeup is handled
    }else{
      cerror(SCHED, "init.requestWakeup %x\r\n", error);
    }
  }

  event void SubCXRQ.wakeupHandled(error_t error, 
      uint8_t layerCount,
      uint32_t atFrame, uint32_t reqFrame){
    if (layerCount){
      signal CXRequestQueue.wakeupHandled(error, 
        layerCount, 
        atFrame, reqFrame);
    }else{
      signal SlotNotify.slotStarted(0);
      if (startDonePending){
        startDonePending = FALSE;
        signal SplitControl.startDone(error);
      }
      if (SUCCESS == error){
        //we consider wake up to be at frame 0 of the cycle.
        uint32_t schedOF = 1;
        lastCycleStart = atFrame;
        //this is the start of the active period. We are master, so we
        //need to send out the schedule.
  
        //if we've made changes, now is the time to swap out the
        //  schedule.
        if (scheduleUpdatePending){
          message_t* swpM = schedMsg;
          cx_schedule_t* swpS = sched;
          cdbg(SCHED, "swap out %p for", schedMsg);
          schedMsg = nextMsg;
          sched = nextSched;
          nextMsg = swpM;
          nextSched = swpS;
          cdbg(SCHED, "%p\r\n", schedMsg);
          scheduleUpdatePending = FALSE;
          call RoutingTable.setDefault(sched->maxDepth);
        }
        //msg setup should happen when it goes through requestSend.
        sched->cycleStartFrame = lastCycleStart;

        call CXPacketMetadata.setTSLoc(schedMsg, &(sched->timestamp));
        error = call ScheduleSend.send(AM_BROADCAST_ADDR,
          schedMsg, sizeof(cx_schedule_t),
          lastCycleStart + schedOF); 
        if (error != SUCCESS){
          cerror(SCHED, "Sched.reqS %x\r\n", error);
        }

        call ScheduleParams.setMasterId(TOS_NODE_ID);
        call ScheduleParams.setSchedule(sched);
        call ScheduleParams.setCycleStart(lastCycleStart);
        //TODO: this should be set somewhat dynamically.
        call ScheduleParams.setSlot(TOS_NODE_ID);
      }else{
        cerror(SCHED, "Sched.wh: %x\r\n", error);
      }
    }
  }

  task void sleepToNextCycle(){
    error_t error;
    error = call SubCXRQ.requestSleep(0,
      lastCycleStart, 
      sched->slotLength*(sched->activeSlots) + 1);
    cinfo(SCHED, "stnc sleep lcs %lu %lu-%lu\r\n", 
      lastCycleStart,
      lastCycleStart + (sched->activeSlots)*sched->slotLength +1,
      lastCycleStart + sched->cycleLength);
    if (error == SUCCESS) {
      error = call SubCXRQ.requestWakeup(0,
        lastCycleStart,
        sched->cycleLength,
        call SkewCorrection.referenceFrame(call CXLinkPacket.addr()),
        call SkewCorrection.referenceTime(call CXLinkPacket.addr()), 
        0);
      cinfo(SCHED, "req cw: %x \r\n",
        error);
    }else{
      cerror(SCHED, "req cycle sleep: %x\r\n",
       error);
    }
  }

  event void SlotNotify.lastSlot(){
    if (scheduleModified){
      cdbg(SCHED, "modified %p next %p\r\n",
        schedMsg, nextMsg);
      scheduleModified = FALSE;
      setNextSchedule(sched->cycleLength, sched->slotLength,
        sched->maxDepth);
    } 
    post sleepToNextCycle();
  }


  command uint32_t CXRequestQueue.nextFrame(bool isTX){
    uint32_t subNext = call SubCXRQ.nextFrame(isTX);
    if (subNext == INVALID_FRAME){
      return INVALID_FRAME;
    }
    if (isTX){
      //we're always synched as master, so rely on slot scheduler to
      //figure out valid time.
      return subNext;
    } else {
      if (lastCycleStart != INVALID_FRAME && sched != NULL){
        //we have a schedule, so we can figure out when our sleep/wake
        //period is.
        uint32_t cycleSleep = lastCycleStart + (sched->slotLength)*(sched->activeSlots)+1;
        uint32_t cycleWake = lastCycleStart;
        while (cycleWake < subNext){
          cycleWake += sched->cycleLength;
        }

        //if subnext is during the sleep period, push it back to
        //1+wake
        if (subNext >= cycleSleep && subNext <= cycleWake){
          return cycleWake + 1;
        }else{
        //otherwise, it's good to go
          return subNext;
        }
      }else{
        //if we don't have a schedule, use result from below.
        return subNext;
      }
    }
  }

  command error_t CXRequestQueue.requestReceive(uint8_t layerCount, 
      uint32_t baseFrame, 
      int32_t frameOffset, 
      bool useMicro, uint32_t microRef,
      uint32_t duration, 
      void* md, message_t* msg){
    if (duration == 0){
      duration = RX_DEFAULT_WAIT;
    }
    return call SubCXRQ.requestReceive(layerCount + 1, baseFrame, frameOffset,
      useMicro, microRef, 
      duration, 
      md, msg);
  }

  event void SubCXRQ.receiveHandled(error_t error, 
      uint8_t layerCount,
      uint32_t atFrame, uint32_t reqFrame, 
      bool didReceive, 
      uint32_t microRef, uint32_t t32kRef,
      void* md, message_t* msg){
    if (didReceive){
      lastSlotActive = TRUE;
    }
    if (layerCount){
      signal CXRequestQueue.receiveHandled(error, layerCount - 1, atFrame, reqFrame,
        didReceive, microRef, t32kRef, md, msg);
    }else{
      cerror(SCHED, "!Unexpected rx handled\r\n");
    }
  }
  
  // in addition to standard layerCount, we also set up the scheduler
  // header: schedule number = current schedule number, originFrame =
  // requested frame, translated to frames since start of cycle
  command error_t CXRequestQueue.requestSend(uint8_t layerCount, 
      uint32_t baseFrame, int32_t frameOffset, 
      tx_priority_t txPriority,
      bool useMicro, uint32_t microRef, 
      void* md, message_t* msg){

    call CXSchedulerPacket.setScheduleNumber(msg, 
      sched->sn);
    call CXSchedulerPacket.setOriginFrame(schedMsg, 
      baseFrame + frameOffset - lastCycleStart);
    call CXNetworkPacket.setTTL(msg, sched->maxDepth);
    call CXLinkPacket.setSource(msg, TOS_NODE_ID);
    return call SubCXRQ.requestSend(layerCount + 1, 
      baseFrame, frameOffset, 
      txPriority,
      useMicro, microRef, 
      md, msg);
  }

  event void SubCXRQ.sendHandled(error_t error, 
      uint8_t layerCount,
      uint32_t atFrame, uint32_t reqFrame, 
      uint32_t microRef, uint32_t t32kRef,
      void* md, message_t* msg){
    lastSlotActive = TRUE;
    if (layerCount){
      signal CXRequestQueue.sendHandled(error, 
        layerCount - 1, 
        atFrame, reqFrame, 
        microRef, t32kRef, 
        md, msg);
    }else{
      cerror(SCHED, "master unexpected SH\r\n");
    }
  }
 

  event void ScheduleSend.sendDone(message_t* msg, error_t error){
    if (SUCCESS == error){
      cinfo(SCHED, "TX sched of %lu ts %lu ofs%lu\r\n",
        call CXNetworkPacket.getOriginFrameNumber(schedMsg),
        sched->timestamp,
        call CXNetworkPacket.getOriginFrameStart(schedMsg));
      call SkewCorrection.addMeasurement(
        call CXLinkPacket.addr(),
        TRUE,
        call CXNetworkPacket.getOriginFrameStart(schedMsg),
        call CXNetworkPacket.getOriginFrameNumber(schedMsg),
        call CXNetworkPacket.getOriginFrameStart(schedMsg));
      //cool. schedule sent.
    }else{
      cerror(SCHED, "!CXMS.SD %x\r\n", error);
      //TODO: handle schedule troubles
    }
  }

  event void AssignmentSend.sendDone(message_t* msg, error_t error){
    cdbg(SCHED, "assign.sd %x\r\n", error);
  }

  command error_t CXRequestQueue.requestSleep(uint8_t layerCount, uint32_t baseFrame, 
      int32_t frameOffset){
    return call SubCXRQ.requestSleep(layerCount + 1, baseFrame, frameOffset);
  }

  event void SubCXRQ.sleepHandled(error_t error, uint8_t layerCount, uint32_t atFrame, 
      uint32_t reqFrame){
    if (layerCount){
      signal CXRequestQueue.sleepHandled(error, layerCount - 1, atFrame, reqFrame);
    }else{
      if (SUCCESS == error){
        lastSleep = atFrame;
      }else{
        cerror(SCHED, "!sched.sh: %x\r\n", error);
      }
    }
  }

  command error_t CXRequestQueue.requestWakeup(uint8_t layerCount, uint32_t baseFrame, 
      int32_t frameOffset, uint32_t refFrame, uint32_t refTime, int32_t correction){
    return call SubCXRQ.requestWakeup(layerCount + 1, baseFrame,
    frameOffset, refFrame, refTime, correction);
  }


  command error_t SplitControl.start(){
    return call SubSplitControl.start();
  }

  command error_t SplitControl.stop(){
    return call SubSplitControl.stop();
  }

  event void SubSplitControl.startDone(error_t error){
    if (error == SUCCESS){
      startDonePending = TRUE;
      sched = (cx_schedule_t*)call ScheduleSend.getPayload(schedMsg, sizeof(cx_schedule_t));
      post initTask();
    }else{
      signal SplitControl.startDone(error);
    }
  }

  event void SubSplitControl.stopDone(error_t error){
    signal SplitControl.stopDone(error);
  }

  task void assignTask(){
    uint8_t i;
    uint8_t reqLeft;
    error_t error;
    cx_assignment_msg_t* pl = (cx_assignment_msg_t*)call AssignmentSend.getPayload(assignMsg, sizeof(cx_assignment_msg_t));
    //TODO: this is not the right interface to call getPayload on
    cx_schedule_request_t* req = (cx_schedule_request_t*)(call AssignmentSend.getPayload(reqMsg, sizeof(cx_schedule_request_t)));

    cdbg(SCHED, "ReqR %u %u\r\n", 
      call CXLinkPacket.getSource(reqMsg),
      req->slotsRequested);

    call Packet.clear(assignMsg);
    reqLeft = req->slotsRequested;
    pl -> numAssigned = 0;
    for (i=0; i < CX_MAX_SLOTS && reqLeft; i++){
      if (assignments[i].status == SA_OPEN){
        scheduleModified = TRUE;
        assignments[i].status = SA_ASSIGNED;
        assignments[i].owner = call CXLinkPacket.getSource(reqMsg);
        assignments[i].csh = 0;
        pl->assignments[pl->numAssigned].owner = assignments[i].owner;
        pl->assignments[pl->numAssigned].slotNumber = i;
        pl->numAssigned++;
        cinfo(SCHED, "a %u to %u\r\n", i, assignments[i].owner);
        reqLeft --;
      }
    }
    error = call AssignmentSend.send(AM_BROADCAST_ADDR, 
      assignMsg, sizeof(cx_assignment_msg_t),
      call CXNetworkPacket.getOriginFrameNumber(reqMsg) + sched->maxDepth + 1);

    cdbg(SCHED, "assign.send %x\r\n", error);

  }

  event message_t* RequestReceive.receive(message_t* msg, 
      void* payload, uint8_t len){
    message_t* swp = reqMsg;
    reqMsg = msg;
    #if TEST_RESELECT == 0
    post assignTask();
    #else
    cdbg(SCHED, "Ignore req\r\n");
    #warning TEST_RESELECT in effect: master will not assign slaves
    //Do nothing.
    #endif
    return swp;

  }

  event void SlotNotify.slotStarted(uint16_t sn){
    //check status of last slot
    if (curSlot < CX_MAX_SLOTS){
      if (assignments[curSlot].status == SA_ASSIGNED){
        if (lastSlotActive){
          //active: reset cycles-since-heard
          assignments[curSlot].csh = 0;
        }else {
          //idle: increment cycles-since-heard. start the freeing
          //process if it's been idle too long
          assignments[curSlot].csh ++;
          cdbg(SCHED, "%u A csh: %u\r\n", 
            curSlot, 
            assignments[curSlot].csh);
          if (assignments[curSlot].csh > EVICTION_THRESHOLD){
            //mark freed and start counting up: we put in some padding
            //between the time when we free the slot and the time when
            //we start letting nodes claim it to help offset the
            //likelihood that a second node claims the same slot as
            //the original owner (that jut happened to miss a few
            //cycles).
            assignments[curSlot].status = SA_FREED;
            assignments[curSlot].csh = 0;
            scheduleModified = TRUE;
          }
        }
      }else if (assignments[curSlot].status == SA_FREED){
        if (lastSlotActive){
          cinfo(SCHED, "%u free but active\r\n", sn);
        } else {
          assignments[curSlot].csh ++;
          //if we marked this freed FREE_TIMEOUT cycles ago, we now
          //update it to be OPEN and can include it in the vacancy
          //announcements.
          cdbg(SCHED, "%u F csh: %u\r\n", 
            curSlot, 
            assignments[curSlot].csh);
          if (assignments[curSlot].csh > FREE_TIMEOUT){
            assignments[curSlot].status = SA_OPEN;
            scheduleModified = TRUE;
          }
        }
      }
    }
    lastSlotActive = FALSE;
    curSlot = sn;
  }
}
