/*
 * Copyright (c) 2014 Johns Hopkins University.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * - Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the
 *   distribution.
 * - Neither the name of the copyright holders nor the names of
 *   its contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL
 * THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
*/


 #include "SettingsStorage.h"
 #include "../BaconSampler/BaconSampler.h"

module SettingsStorageP {
  provides interface SettingsStorage;

  uses interface TLVStorage;
  uses interface TLVUtils;
  uses interface Boot;
  uses interface LogWrite;
  uses interface Get<uint16_t> as RebootCounter;
  uses interface LocalTime<TMilli>;

  uses interface Leds;
} implementation {

  //TODO: un-hardcode this. Should be based on some platform
  //TLVStorage len constant.
  uint8_t tlvs[128];
  bool loaded = FALSE;

  #if ENABLE_TIME_SYNC == 1
  //Used to indicate if the request is to send timesync info or change some 
  //settings.
  bool is_Timesync = FALSE;
  #endif

  command error_t SettingsStorage.get(uint8_t key, void* val, uint8_t len){
    tlv_entry_t* entry;
    error_t ret = SUCCESS;
    if (! loaded){
      ret = call TLVStorage.loadTLVStorage(tlvs);
      loaded = TRUE;
    }
    if (ret == SUCCESS){
      uint8_t tlvi = call TLVUtils.findEntry(key, 0, &entry, tlvs);
      if (tlvi){
        if (entry->len == len){
          memcpy(val, &(entry->data), len);
          return SUCCESS;
        } else{
          return ESIZE;
        }
      }else{
        return EINVAL;
      }
    }else{
      return ret;
    }
  }
 
  settings_record_t rec = {.recordType=RECORD_TYPE_SETTINGS};

  #if ENABLE_TIME_SYNC == 1
  //time_sync information is recorded as Bacon_sample record.
  bacon_sample_t time_sync_rec = {
    .recordType = RECORD_TYPE_BACON_SAMPLE,
    .rebootCounter = 0xffff,
    .baseTime = 0,
    .battery = 0xffff,
    .light = 0xffff,
    .thermistor = 0xffff
  };
  #endif

  bool logging;
  enum {
    S_IDLE=0x00,
    S_LOG_FIRST = 0x01,
    S_LOG_SECOND = 0x02,
  };
  uint8_t logState = S_IDLE;

  task void logSettings1(){
    if (logState == S_IDLE){
      if (! loaded){
        error_t error = call TLVStorage.loadTLVStorage(tlvs);
        if (error == SUCCESS){
          loaded = TRUE;
        }
      }
      if (loaded){
        logState = S_LOG_FIRST;
        rec.rebootCounter = call RebootCounter.get();
        rec.ts = call LocalTime.get();
        rec.offset = 0;
        memcpy(&rec.data, tlvs, SETTINGS_CHUNK_SIZE);
        if (SUCCESS == call LogWrite.append(&rec, sizeof(rec))){
          //cool
        }else {
          logState = S_IDLE;
        }
      }
    }
  }

  task void logSettings2(){
    if (logState == S_LOG_FIRST){
      logState = S_LOG_SECOND;
      rec.offset = SETTINGS_CHUNK_SIZE;
      memcpy(&rec.data, &tlvs[SETTINGS_CHUNK_SIZE], SETTINGS_CHUNK_SIZE);
      if (SUCCESS == call LogWrite.append(&rec, sizeof(rec))){
        //cool
      }else {
        logState = S_IDLE;
      }
    }else{
      //unexpected state
    }
  }

  event void LogWrite.appendDone(void* buf, storage_len_t len, 
      bool recordsLost, error_t error){

  #if ENABLE_TIME_SYNC == 1
    if(is_Timesync)
      return;
  #endif

    if (error == SUCCESS){
      if (logState == S_LOG_FIRST){
        post logSettings2();
      }else {
        logState = S_IDLE;
      }
    } else {
      //ruh-roh
      logState = S_IDLE;
    }
  }

  event void LogWrite.eraseDone(error_t error){}
  event void LogWrite.syncDone(error_t error){}
  
  event void Boot.booted(){
    post logSettings1();
  }

  command error_t SettingsStorage.set(uint8_t key, void* val, uint8_t len){
    tlv_entry_t* entry;
    error_t ret = SUCCESS;

    #if ENABLE_TIME_SYNC == 1
    if(key == SS_KEY_TIME_SYNC)
    {
      is_Timesync = TRUE;
      memcpy(&time_sync_rec.baseTime, val, len);
      ret = call LogWrite.append(&time_sync_rec, sizeof(time_sync_rec));
      return ret;
    }
    else
      is_Timesync = FALSE;
    #endif

    if (!loaded){
      ret = call TLVStorage.loadTLVStorage(tlvs);
      loaded = TRUE;
    }
    if (ret == SUCCESS){
      uint8_t tlvi = call TLVUtils.findEntry(key, 0, &entry, tlvs);
      if (tlvi){
        //entry is now pointing at an existing one: remove it so that
        //we can insert a new one (required for safety if we are going
        //to change the size of an entry, for instance)
        call TLVUtils.deleteEntry(tlvi, tlvs);
//        memcpy(&(entry->data), val, len);
      } 
      {
        //addEntry uses somewhat different semantics: need to
        //give it a pointer to an already-filled-in tlv_entry_t
        //ugh.
        tlv_entry_t e;
        e.tag = key;
        e.len = len;
        memcpy(&(e.data), val, len);
        //not found? new entry.
        tlvi = call TLVUtils.addEntry(key, len, &e, tlvs, 0);
        if (! tlvi){
          call TLVStorage.loadTLVStorage(tlvs);
          //not enough space to add entry. Restore previous version.
          return ESIZE;
        }
      }
      ret = call TLVStorage.persistTLVStorage(tlvs);
      if (ret == SUCCESS){
        loaded = FALSE;
        ret = call TLVStorage.loadTLVStorage(tlvs);
        if (ret == SUCCESS){
          loaded = TRUE;
        }
      } 
      post logSettings1();
      return ret;
    }else{
      return ret;
    }
  }

  command error_t SettingsStorage.clear(uint8_t key){
    tlv_entry_t* entry;
    error_t ret = call TLVStorage.loadTLVStorage(tlvs);
    if (ret == SUCCESS){
      uint8_t tlvi = call TLVUtils.findEntry(key, 0, &entry, tlvs);
      if (! tlvi){
        return EINVAL;
      }else{
        ret = call TLVUtils.deleteEntry(tlvi, tlvs);
        post logSettings1();
        if (ret == SUCCESS){
          return call TLVStorage.persistTLVStorage(tlvs);
        }else{
          return ret;
        }
      }
    } else {
      return ret;
    }
  }
 
  
  task void signalAD(){
    signal LogWrite.appendDone(NULL, 0, FALSE, SUCCESS);
  }

  default command error_t LogWrite.append(void* buf, storage_len_t len){
    post signalAD();
    return SUCCESS;
  }
}
