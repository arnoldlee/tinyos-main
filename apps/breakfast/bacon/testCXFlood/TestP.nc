/**
 * Application-level usage of CX flood primitive
 * 
 * @author Doug Carlson <carlson@cs.jhu.edu>
 */

#include "testCXFlood.h"
#include <stdio.h>
#include "decodeError.h"

module TestP {
  uses interface Boot;
  uses interface Timer<TMilli>;
  uses interface StdControl as UartControl;
  uses interface UartStream;

  uses interface AMSend;
  uses interface AMPacket;
  uses interface Receive;

  uses interface CXFloodControl;

  uses interface SplitControl;

  uses interface Rf1aPhysical;
  uses interface HplMsp430Rf1aIf;
} implementation {
  bool isSending;
  bool isOn = FALSE;
  bool isRoot = FALSE;
  message_t msg_internal;
  message_t* _msg = &msg_internal;

  void printState(){
    printf("Current State\n\r");
    printf(" isOn: %x\n\r", isOn);
    printf(" isRoot: %x\n\r", isRoot);
    printf(" isSending: %x\n\r", isSending);
  }

  event void Boot.booted(){
    //timing pins
    P1SEL &= ~(BIT1|BIT3|BIT4);
    P1SEL |= BIT2;
    P1DIR |= (BIT1|BIT2|BIT3|BIT4);
    P2SEL &= ~(BIT4);
    P2DIR |= (BIT4);
    //set up SFD GDO on 1.2
    atomic{
      PMAPPWD = PMAPKEY;
      PMAPCTL = PMAPRECFG;
      P1MAP2 = PM_RFGDO0;
      PMAPPWD = 0x00;
    }

    call UartControl.start();
    printf("Booted\n\r");
    printf(" r: toggle root on/off\n\r");
    printf(" s: start/stop AM\n\r");
    printf(" t: start/stop transmitting\n\r");
    printState();
    call CXFloodControl.setRoot(isRoot);
  }

  event void SplitControl.stopDone(error_t error){
    printf("Stopped: %s\n\r", decodeError(error));
    isOn = FALSE;
    printState();
  }

  event void SplitControl.startDone(error_t error){
//    printf("Started: %s\n\r", decodeError(error));
    isOn = TRUE;
//    printState();
  }

  error_t sendError;
  task void reportSend(){
    test_packet_t* pl = call AMSend.getPayload(_msg,
      sizeof(test_packet_t));
    printf("Send: %lu %s\n\r", pl->seqNum,
      decodeError(sendError));
  }

  event void Timer.fired(){
    error_t error;
    test_packet_t* pl = call AMSend.getPayload(_msg,
      sizeof(test_packet_t));
    pl -> seqNum += 2;
    error = call AMSend.send(AM_BROADCAST_ADDR, _msg, sizeof(test_packet_t));
    post reportSend();
  }

  async event void UartStream.receivedByte(uint8_t byte){
    switch(byte){
      case 'q':
        WDTCTL=0;
        break;
      case '\r':
        printf("\n\r");
        break;
      case 's':
        if (isOn){
          printState();
          printf("Stop: %s\n\r", decodeError(call SplitControl.stop()));
        } else {
          printState();
          printf("Start: %s\n\r", decodeError(call SplitControl.start()));
        }
        break;
      case 'r':
        isRoot = !isRoot;
        printf("Set root to %x: %s\n\r", 
          isRoot, decodeError(call CXFloodControl.setRoot(isRoot)));
        if (isRoot){
          call CXFloodControl.claimFrame(1);
        }
        break;
      case 't':
        isSending = !isSending;
        printf("Is sending: %x\n\r", isSending);
        if (!isSending && call Timer.isRunning()){
          call Timer.stop();
        }
        if (isSending && ! call Timer.isRunning()){
          call Timer.startOneShot(1);
        }
        break;
      default:
        printf("%c", byte);
        break;
    }
  }

  error_t sendDoneError;
  task void reportSendDone(){
    printf("APP sendDone: %s\n\r", decodeError(sendDoneError));
  }

  event void AMSend.sendDone(message_t* msg, error_t error){
    sendDoneError = error;
    post reportSendDone();
    if (isSending){
      call Timer.startOneShot(SEND_PERIOD);
    }
  }

  uint32_t lastSn;
  uint16_t lastSrc;

  event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
    test_packet_t* pl = (test_packet_t*)payload;
    lastSn = pl->seqNum;
    lastSrc = call AMPacket.source(msg);
    printf("APP Received %u %lu\n\r", lastSrc, lastSn);
    return msg;
  }

  event void CXFloodControl.noSynch(){
    error_t error;
    printf("No synch! Try to restart.\n\r");
    error = call SplitControl.start();
    printf("sc.start: %s\n\r", decodeError(error));
  }

  event void CXFloodControl.synchInfo(uint32_t period, 
      uint32_t frameLen, uint16_t numFrames){
    error_t error;
    printf("Synch obtained: period %lu frameLen %lu frames %u\n\r",
      period, frameLen, numFrames);
    error = call CXFloodControl.claimFrame(TOS_NODE_ID);
    printf("Claim %d: %s\n\r", TOS_NODE_ID, decodeError(error));
  }

  //unused events
  async event void UartStream.receiveDone( uint8_t* buf_, uint16_t len,
    error_t error ){}
  async event void UartStream.sendDone( uint8_t* buf_, uint16_t len,
    error_t error ){}

  async event void Rf1aPhysical.sendDone (int result) { }
  async event void Rf1aPhysical.receiveStarted (unsigned int length) { }
  async event void Rf1aPhysical.receiveDone (uint8_t* buffer,
                                             unsigned int count,
                                             int result) { }
  async event void Rf1aPhysical.receiveBufferFilled (uint8_t* buffer,
                                                     unsigned int count) { }
  async event void Rf1aPhysical.frameStarted () { }
  async event void Rf1aPhysical.clearChannel () { }
  async event void Rf1aPhysical.carrierSense () { }
  async event void Rf1aPhysical.released () { }

}

/* 
 * Local Variables:
 * mode: c
 * End:
 */
