#include "hamming74.h"
#include <stdio.h>
#include "FECDebug.h"

module Hamming74Rf1aFifoP{
  provides interface Rf1aFifo;
  uses interface HplMsp430Rf1aIf as Rf1aIf;
} implementation {
  #define FEC_BUF_LEN 64
  uint8_t encodedBuf[FEC_BUF_LEN];

  async command uint8_t Rf1aFifo.getEncodedLen(uint8_t decodedLen){
    return 2*decodedLen;
  }

  async command uint8_t Rf1aFifo.getDecodedLen(uint8_t encodedLen){
    return encodedLen>>1;
  }

  async command error_t Rf1aFifo.readRXFIFO(uint8_t* buf, uint8_t dataBytes, 
      bool isControl){
    printf_FEC("R %u %x ", dataBytes, isControl);
    if (isControl){
      call Rf1aIf.readBurstRegister(RF_RXFIFORD, buf, dataBytes);
      printf_FEC("(%x)\r\n", *buf);
      return SUCCESS;
    } else {
      if (call Rf1aFifo.getEncodedLen(dataBytes) > FEC_BUF_LEN){
        return ESIZE;
      }else{
        uint8_t i;
        uint8_t d;
        error_t ret = SUCCESS;

        printf_FEC("[ ");
        call Rf1aIf.readBurstRegister(RF_RXFIFORD, encodedBuf,
          dataBytes*2);
        //TODO: should check for invalid encodings here? or just plan
        //on putting in a checksum
        for (i = 0; i < call Rf1aFifo.getEncodedLen(dataBytes); i++){
          d = decoding[encodedBuf[i]];
//          printf_FEC("%02X ", encodedBuf[i]);
          if (i&0x01){
            buf[i>>1] |= d;
            printf_FEC("%02X ", buf[i>>1]);
          }else{
            buf[i>>1] = d << 4;
          }
          //0xff indicates error in decoding table
          if (d == 0xff){
            ret = FAIL;
          }
        }
        printf_FEC("]\r\n");
        return ret;
      }
    }
  } 

  //We're encoding big-end first: the high order nibble of byte i goes
  //  into the buffer at 2*i, low-order nibble at 1+2*i
  async command error_t Rf1aFifo.writeTXFIFO(const uint8_t* buf, uint8_t dataBytes, 
      bool isControl){
//    printf_FEC("W %u %x\r\n", dataBytes, isControl);
    if (isControl){
      call Rf1aIf.writeBurstRegister(RF_TXFIFOWR, buf,
        dataBytes);
      return SUCCESS;
    } else {
      if (call Rf1aFifo.getEncodedLen(dataBytes) > FEC_BUF_LEN){
        return ESIZE;
      }else{
        uint8_t i;
        for (i=0; i < dataBytes; i++){
          //would like this to be more flexible so we can change the
          //encoding.
          encodedBuf[2*i] = encoding[buf[i] >> 4];
          encodedBuf[(2*i)+1] = encoding[(buf[i] & 0x0f)];
          call Rf1aIf.writeBurstRegister(RF_TXFIFOWR, &encodedBuf[2*i], 2);
        }
//        call Rf1aIf.writeBurstRegister(RF_TXFIFOWR, encodedBuf, 
//          call Rf1aFifo.getEncodedLen(dataBytes));
        return SUCCESS;
      }
    }
  }
  
}
