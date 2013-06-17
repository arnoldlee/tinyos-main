#ifndef CX_MAC_H
#define CX_MAC_H

#include "CXLink.h"

#define CXM_DATA 0
#define CXM_PROBE 1
#define CXM_KEEPALIVE 2
#define CXM_CTS 3
#define CXM_RTS 4
//TODO: maybe add acks

typedef nx_struct cx_mac_header{
  nx_uint8_t macType;
} cx_mac_header_t;

#ifndef LPP_DEFAULT_PROBE_INTERVAL
#define LPP_DEFAULT_PROBE_INTERVAL 5120UL
#endif

#ifndef LPP_SLEEP_TIMEOUT
#define LPP_SLEEP_TIMEOUT 30720UL
#endif

#define CX_KEEPALIVE_RETRY 512UL

//0.03125 s * 1.5 = 0.046875 s
#define CHECK_TIMEOUT (FRAMELEN_FAST + (FRAMELEN_FAST/2))
//add 50% for safety
#define CHECK_TIMEOUT_SLOW 72UL

//roughly 660 seconds
#define RX_TIMEOUT_MAX (0xFFFFFFFF)
//Add 50% for safety
#define RX_TIMEOUT_MAX_SLOW 1014934UL

#define MAC_RETRY_LIMIT 4

#ifndef CX_BASESTATION 
#define CX_BASESTATION 0
#endif

//Basestation control messages
typedef nx_struct cx_lpp_wakeup {
  nx_uint32_t timeout;
} cx_lpp_wakeup_t;

typedef nx_struct cx_lpp_sleep {
  nx_uint32_t delay;
} cx_lpp_sleep_t;

typedef nx_struct cx_lpp_cts {
  nx_am_addr_t addr;
} cx_lpp_cts_t;

enum {
 AM_CX_LPP_WAKEUP=0xC6,
 AM_CX_LPP_SLEEP=0xC7,
 AM_CX_LPP_CTS=0xC8,
};

#endif