#ifndef SCHEDULE_H
#define SCHEDULE_H

#include "Rf1aPacket.h"
#include "CX.h"

#define AM_ID_LEAF_SCHEDULE 0xE0
#define AM_ID_LEAF_REQUEST 0xE1
#define AM_ID_LEAF_RESPONSE 0xE2

#define AM_ID_ROUTER_SCHEDULE 0xF0
#define AM_ID_ROUTER_REQUEST 0xF1
#define AM_ID_ROUTER_RESPONSE 0xF2

#define CX_SCHEDULER_MASTER 0x00
#define CX_SCHEDULER_SLAVE 0x01

#ifndef MAX_ANNOUNCED_SLOTS
#define MAX_ANNOUNCED_SLOTS 10
#endif

#ifndef SCHED_NUM_SLOTS
#define SCHED_NUM_SLOTS 10
#endif

#ifndef SCHED_FRAMES_PER_SLOT
#define SCHED_FRAMES_PER_SLOT 10
#endif

#ifndef CX_RESYNCH_CYCLES
#define CX_RESYNCH_CYCLES 5
#endif

#ifndef CX_TIMEOUT_CYCLES
#define CX_KEEPALIVE_CYCLES 10
#endif

#ifndef SCHED_INIT_SYMBOLRATE
#define SCHED_INIT_SYMBOLRATE 125
#endif

#ifndef SCHED_INIT_CHANNEL
#define SCHED_INIT_CHANNEL 0
#endif

#ifndef SCHED_MAX_DEPTH
#define SCHED_MAX_DEPTH 8
#endif

enum {
  UNCLAIMED = 0xffff,
  INVALID_SCHEDULE_NUM= 0xff,
  INVALID_SLOT = 0xffff,
};

typedef struct assignment_t {
  am_addr_t owner;
  uint8_t absentCycles;
  bool notified;
} assignment_t;

#if STATIC_SCHEDULER == 0
typedef nx_struct cx_schedule_t {
  nx_uint8_t scheduleNum;  //incremented if any parameters change
                           // which would result in a synch loss were
                           // they not received
  nx_uint8_t symbolRate;   //data rate in kbps
  nx_uint8_t channel;
  nx_uint16_t slots;      //total slots in cycle
  nx_uint16_t framesPerSlot; 
  nx_uint8_t  maxRetransmit;
  nx_uint16_t firstIdleSlot; //range of cycle with no traffic
  nx_uint16_t lastIdleSlot;
  nx_uint16_t availableSlots[MAX_ANNOUNCED_SLOTS]; //the free slots
} cx_schedule_t;
#else
#if RF1A_FEC_ENABLED == 1
#define SCHED_PADDING_LEN 0
#else
#define SCHED_PADDING_LEN (sizeof(ieee154_header_t) + sizeof(cx_header_t) + sizeof(rf1a_nalp_am_t) + sizeof(nx_uint8_t) + 2*sizeof(uint16_t))
#endif
typedef nx_struct cx_schedule_t {
  nx_uint8_t scheduleNum;  //incremented if any parameters change
                           // which would result in a synch loss were
                           // they not received
  nx_uint8_t padding[SCHED_PADDING_LEN];
} cx_schedule_t;
#endif

typedef nx_struct cx_request_t {
  nx_uint16_t slotNumber;
} cx_request_t;

typedef nx_struct cx_response_t {
  nx_am_addr_t owner;
  nx_uint16_t slotNumber;
} cx_response_t;

#endif
