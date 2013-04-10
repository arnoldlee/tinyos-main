#ifndef CX_TRANSPORT_H
#define CX_TRANSPORT_H

typedef nx_struct cx_transport_header {
  nx_uint8_t tproto;
} cx_transport_header_t;

#define CX_TP_FLOOD_BURST 0x00
#define CX_TP_RR_BURST 0x00

//lower nibble is available for distinguishing data/ack/setup, etc
#define CX_TP_PROTO_MASK 0xF0

#endif
