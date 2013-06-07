module CXActivitySchedulerP {
  //with layer above: 
  // - handle to current schedule (cycle length, slot
  //   length)
  // - mechanism to anchor the cycle in time
  // - mechanism to force an immediate sleep.
  uses interface Get<cx_schedule_t*>;
  provides interface ActivityScheduler;
  
  //Layer below: CXLink provides tone rx/tx, sleep, and rx-with-timeout
  uses interface CXLink;
   

  //A single pending send is queued here.
  //- Each message that reaches this layer has a slot number in its
  //  metadata indicating when it should be sent.
  //- When a slot starts and its number matches the pending TX, we
  //  send a wakeup tone to notify the network and synch it, then
  //  send the packet (via flood).
  provides interface Send;
  uses interface Send as SubSend;

  //Receives are largely passed-through, though their timing
  //information is extracted to set the wakeup schedule within the
  //slot.
  provides interface Receive;
  uses interface Receive as SubReceive;

  //This timer is used to listen/send tone at slot start.
  uses interface Timer<T32Khz> as SlotTimer;
  //This timer is used once a tone is sent/received to set the valid
  //times where we expect a packet or may send a packet.
  uses interface Timer<T32Khz> as FrameTimer;

} implementation {
  #define sched (call Get.get())

  //Main cycle flow is handled above this layer.
  //- The layer above (master/slave) tells this layer what slot it is on
  //  and what time that slot began.
  //- This layer starts its slot timer as instructed.
  command error_t ActivityScheduler.setSlotStart(
      uint16_t atSlotNumber, uint32_t t0, uint32_t dt){
    if (call SlotTimer.running()){
      call SlotTimer.stop();
    }
    slotNumber = atSlotNumber == 0 ? sched->numSlots : (atSlotNumber - 1);
    call SlotTimer.startOneShotAt(t0, dt);
  }
  

  //Slot cycle flow
  //- A new slot starts, and the state (slot number/frame number) are
  //  updated.
  //- If the schedule (from above) indicates this is an inactive slot,
  //  we sleep immediately.
  //- If we have a pending TX for this slot, we send the wakeup tone.
  //- Otherwise, we listen for a wakeup tone.
  event void SlotTimer.fired(){
    slotNumber = (slotNumber+1)%(sched->numSlots);
    frameNumber = 0;
    call SlotTimer.startOneShot(sched->slotLength);
    signal ActivitySchedule.slotStarted(slotNumber);

    if (txMsg && slotNumber(txMsg) == slotNumber){
      call CXLink.txTone();
    }else if (slotNumber <= sched->activeSlots){
      call CXLink.rxTone();
    }else{
      call CXLink.sleep();
    }
  }
  

  //Start of Slot behavior
  //- No wakeup received: sleep until next slot.
  //- Wakeup received: start frame duty cycling based on reception
  //  time.
  //- Wakeup sent: start frame duty cycling based on TX time.
  event void CXLink.toneReceived(bool received, uint32_t refTime){
    if (!received){
      call CXLink.sleep();
    }else{
      //TODO: assign rx timeout here: if we correctly synch at the end
      //of this, then we can use a short timeout. If we have no synch
      //at all, then this should be FRAMELEN_SLOW*maxDepth
      call FrameTimer.startPeriodic(FRAMELEN_SLOW);
    }
  }
  event void CXLink.toneSent(uint32_t refTime){
    call FrameTimer.startPeriodicAt(refTime, FRAMELEN_SLOW);
  }
  
  //Once the start-of-slot behavior is resolved, we move on to some
  //  sequence of frame activities.

  //Frame Activities: do the next whenever the frame timer fires.
  //- If the layer below is busy (sending or receiving/forwarding),
  //  then do nothing.
  //- If there's a packet pending for this slot, send it.
  //- Otherwise, try to do an RX.
  event void FrameTimer.fired(){
    if (frameNumber >= sched->slotLength){
      call FrameTimer.stop();
    }else{
      //we're busy.
      if (sending || receiving){
        //do nothing
      
      //we have a pending TX for this slot, and there's time to send
      //it.
      } else if (txMsg && slotNumber(txMsg) == slotNumber 
          && (call SlotTimer.nextAlarm() - call TXTimer.now() > (FRAMELEN_SLOW*TTL))){
        //TODO: may need to push this a little forward so that RX
        //  starts first.
        call SubSend.send(txMsg);
      } else {
        call CXLink.rx(rxTimeout);
        receiving = TRUE;
      }
    }
  }

  //CXLink call-backs
  //These indicate that an event started in FrameTimer.fired() has
  //completed, and the radio is free to do something else the next
  //time that FrameTimer fires.
  event void SubSend.sendDone(){
    sending = FALSE;
    txMsg = NULL;
    signal Send.sendDone();
  }
  event void CXLink.rxDone(){
    receiving = FALSE;
  }

  //Send queue management
  //- A single txMsg may be queued at a time. it has an associated
  //  slot number in its metadata (from layers above).
  //- If a closer txMsg is send'ed, the preceding one will get booted
  //  out (sendDone(ERETRY)). 
  //- If there is a message queued already that is sooner than the one
  //  being send'ed, then the send will return EBUSY.
  //- We permit send cancellation as long as the tx hasn't already
  //  started: this allows the upper layers (e.g. role-switcher) to
  //  focus on managing the tx ordering, not this layer.
  command error_t Send.send(message_t* msg, uint8_t len){
    if (txMsg == NULL){
      txMsg = msg;
    } else {
      if (slotsFromNow(msg) < slotsFromNow(txMsg)){
        signal Send.sendDone(txMsg, ERETRY);
        txMsg = msg;
      } else{
        return EBUSY;
      }
    }
    return SUCCESS;
  }
  command error_t Send.cancel(message_t* msg){
    if (txMsg == msg && !sending){
      txMsg = NULL;
      return SUCCESS;
    }else{
      return FAIL;
    }
  }
 
  //Send/receive 
  //As these events pass through, adjust the frame schedule.
  event message_t* SubReceive.receive(message_t* msg, 
      void* pl, uint8_t len){
    //TODO: extract frame timing from this reception: packet is
    //timestamped with 32K arrival (which may be several frames back).
    //We should stop the frame timer, set its base to the 32K arrival
    //time - slack + (frames-elapsed), then start it up again.
    return signal Receive.receive(msg, pl, len);
  }
  event void Send.sendDone(message_t* msg, error_t error){
    //TODO: extract frame timing from this transmission.
    sending = FALSE;
    signal Send.sendDone(msg, error);
  }

  //Force the radio to sleep
  command error_t ActivityScheduler.sleep(){
    //TODO: clean up any other state you might have going on
    call FrameTimer.stop();
    return call CXLink.sleep();
  }

  command error_t ActivityScheduler.stop(){
    //stop things all together.
    call SlotTimer.stop();
    return call ActivityScheduler.sleep();
  }
  

  //utility/bookkeeping functions
  uint16_t slotNumber(message_t* msg){
    //TODO: pull slot number from metadata
    return 0;
  }
  uint16_t slotsFromNow(message_t* msg){
    //TODO: use current slot, cycle length, and slotNumber(msg) to
    //figure out how many slots away it is.
    return 0;
  }
  
  #undef sched
}

