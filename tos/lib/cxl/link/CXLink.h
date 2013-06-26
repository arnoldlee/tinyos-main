#ifndef CX_LINK_H
#define CX_LINK_H

#include "AM.h"

#ifndef CX_SCALE_TIME
#define CX_SCALE_TIME 1
#endif

#ifndef FRAMELEN_SLOW
//32k = 2**15
#define FRAMELEN_SLOW (1024UL * CX_SCALE_TIME)
#endif

#ifndef FRAMELEN_FAST_NORMAL
//6.5M = 2**5 * 5**16 * 13
#define FRAMELEN_FAST_NORMAL (203125UL * CX_SCALE_TIME)
#endif

#ifndef FRAMELEN_FAST_SHORT
//set to 4.4 ms: short packet is estimated to take 1.1 ms to send,
//add an equal amount of padding time 
//#define FRAMELEN_FAST_SHORT (84500UL * CX_SCALE_TIME)
//#define FRAMELEN_FAST_SHORT (90000UL * CX_SCALE_TIME)
//#define FRAMELEN_FAST_SHORT FRAMELEN_FAST_NORMAL
#define FRAMELEN_FAST_SHORT 19500UL
#endif

//TODO: these should be based on sizeof's/whether FEC is in use.
//Short packet: mac header only
#define SHORT_PACKET 12
//Long packet: at least 64 bytes, when encoded (also: 2 byte crc)
#define LONG_PACKET 30

//worst case: 8 byte-times (preamble, sfd)
//(64/125000.0)*6.5e6=3328, round up a bit.
#define CX_CS_TIMEOUT_EXTEND 3500UL

//time from strobe command to SFD: 0.000523 S
//argh, this looks less constant than I want it to be...
#define TX_SFD_ADJUST 3346UL

//difference between transmitter SFD and receiver SFD: 60.45 fast ticks
#define T_SFD_PROP_TIME_FAST (60UL - 12UL)
#define T_SFD_PROP_TIME_NORMAL (60UL)

#define RX_SFD_ADJUST_FAST   (TX_SFD_ADJUST + T_SFD_PROP_TIME_FAST)
#define RX_SFD_ADJUST_NORMAL (TX_SFD_ADJUST + T_SFD_PROP_TIME_NORMAL)


typedef nx_struct cx_link_header {
  nx_uint8_t ttl;
  nx_uint8_t hopCount;
  nx_am_addr_t destination;
  nx_am_addr_t source;
  nx_uint32_t sn;
  nx_uint8_t bodyLen;
} cx_link_header_t;

typedef struct cx_link_metadata {
  uint8_t rxHopCount;
  uint32_t time32k;
  bool retx;
  nx_uint32_t* tsLoc;
} cx_link_metadata_t;


#ifndef CX_MAX_DEPTH
#define CX_MAX_DEPTH 10
#endif

#endif
