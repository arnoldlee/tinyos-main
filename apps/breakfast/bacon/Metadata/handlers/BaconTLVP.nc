module BaconTLVP{
  uses interface Packet;
  uses interface AMPacket;
  uses interface Pool<message_t>;
  uses interface TLVStorage;
  uses interface TLVUtils;

  uses interface Receive as ReadBaconTlvCmdReceive;
  uses interface Receive as WriteBaconTlvCmdReceive;
  uses interface Receive as DeleteBaconTlvEntryCmdReceive;
  uses interface Receive as AddBaconTlvEntryCmdReceive;
  uses interface Receive as ReadBaconTlvEntryCmdReceive;

  uses interface AMSend as ReadBaconTlvResponseSend;
  uses interface AMSend as WriteBaconTlvResponseSend;
  uses interface AMSend as DeleteBaconTlvEntryResponseSend;
  uses interface AMSend as AddBaconTlvEntryResponseSend;
  uses interface AMSend as ReadBaconTlvEntryResponseSend;

  uses interface AMSend as WriteBaconVersionResponseSend;
  uses interface AMSend as WriteBaconBarcodeIdResponseSend;

  uses interface AMSend as ReadBaconVersionResponseSend;
  uses interface AMSend as ReadBaconBarcodeIdResponseSend;

} implementation {
  message_t* responseMsg = NULL;
  message_t* cmdMsg = NULL;
  am_id_t currentCommandType; 

  //TODO: param
  #define BACON_TLV_LEN 128
  uint8_t tlvs_buf[BACON_TLV_LEN];
  void* tlvs = tlvs_buf;
  
  task void handleLoaded();
  task void persisted();

  task void respondReadBaconTlv();
  task void respondWriteBaconTlv();
  task void respondDeleteBaconTlvEntry();
  task void respondAddBaconTlvEntry();
  task void respondReadBaconTlvEntry();

  void cleanup(){
    if (responseMsg != NULL){
      call Pool.put(responseMsg);
      responseMsg = NULL;
    }
    if (cmdMsg != NULL){
      call Pool.put(cmdMsg);
      cmdMsg = NULL;
    }
    currentCommandType = 0;
  }
  
  error_t loadTLVError;
  error_t persistTLVError;

  task void loadTLVStorage(){
    loadTLVError = call TLVStorage.loadTLVStorage(tlvs);
    post handleLoaded();
  }

  error_t persistTLVStorage(void* tlvs_){
    persistTLVError = call TLVStorage.persistTLVStorage(tlvs_);
    if (persistTLVError == SUCCESS){
      post persisted();
    }
    return persistTLVError;
  }

  task void handleLoaded(){
    printf("Loaded bacon TLV e %x c %x\n", loadTLVError,
      currentCommandType);
    printfflush();
    if (loadTLVError == SUCCESS){
      switch (currentCommandType){
        case AM_READ_BACON_TLV_CMD_MSG:
          post respondReadBaconTlv();
          break;
        case AM_DELETE_BACON_TLV_ENTRY_CMD_MSG:
          post respondDeleteBaconTlvEntry();
          break;
        case AM_ADD_BACON_TLV_ENTRY_CMD_MSG:
          post respondAddBaconTlvEntry();
          break;
        case AM_READ_BACON_TLV_ENTRY_CMD_MSG:
          printf("loaded: read generic\n");
          printfflush();
          post respondReadBaconTlvEntry();
          break;
        default:
          printf("Unknown command %x\n", currentCommandType);
      }
    } else {
      read_bacon_tlv_response_msg_t* responsePl = 
        (read_bacon_tlv_response_msg_t*)(call Packet.getPayload(responseMsg, sizeof(read_bacon_tlv_response_msg_t)));
      responsePl->error = loadTLVError;
      switch (currentCommandType){
        case AM_READ_BACON_TLV_CMD_MSG:
          call ReadBaconTlvResponseSend.send(0, responseMsg, 
            sizeof(read_bacon_tlv_response_msg_t));
          break;
        case AM_DELETE_BACON_TLV_ENTRY_CMD_MSG:
          call DeleteBaconTlvEntryResponseSend.send(0, responseMsg, 
            sizeof(delete_bacon_tlv_entry_response_msg_t));
          break;
        case AM_ADD_BACON_TLV_ENTRY_CMD_MSG:
          call AddBaconTlvEntryResponseSend.send(0, responseMsg, 
            sizeof(add_bacon_tlv_entry_response_msg_t));
          break;
        case AM_READ_BACON_TLV_ENTRY_CMD_MSG:
          call ReadBaconTlvEntryResponseSend.send(0, responseMsg, 
            sizeof(read_bacon_tlv_entry_response_msg_t));
          break;
        default:
          printf("Unrecognized current command: %x\n",
            currentCommandType);
          break;
      }
      currentCommandType = 0;
    }
  }
  
  task void persisted(){
    add_bacon_tlv_entry_cmd_msg_t* commandPl = (add_bacon_tlv_entry_cmd_msg_t*)(call Packet.getPayload(cmdMsg, sizeof(add_bacon_tlv_entry_cmd_msg_t)));
    add_bacon_tlv_entry_response_msg_t* responsePl = (add_bacon_tlv_entry_response_msg_t*)(call Packet.getPayload(responseMsg, sizeof(add_bacon_tlv_entry_response_msg_t)));
    responsePl->error = persistTLVError;
    switch(currentCommandType){
      case AM_ADD_BACON_TLV_ENTRY_CMD_MSG:
        switch(commandPl->tag){
          case TAG_VERSION:
            call WriteBaconVersionResponseSend.send(0, responseMsg, sizeof(add_bacon_tlv_entry_response_msg_t));
            break;
          case TAG_GLOBAL_ID:
            call WriteBaconBarcodeIdResponseSend.send(0, responseMsg, sizeof(add_bacon_tlv_entry_response_msg_t));
            break;
          default:
            call AddBaconTlvEntryResponseSend.send(0, responseMsg, sizeof(add_bacon_tlv_entry_response_msg_t));
            break;
        }
        break;
      case AM_DELETE_BACON_TLV_ENTRY_CMD_MSG:
        call DeleteBaconTlvEntryResponseSend.send(0, responseMsg, sizeof(delete_bacon_tlv_entry_response_msg_t));
        break;
      case AM_WRITE_BACON_TLV_CMD_MSG:
        call WriteBaconTlvResponseSend.send(0, responseMsg, sizeof(write_bacon_tlv_response_msg_t));
        break;
      default:
        printf("Unrecognized command: %x\n", currentCommandType);
    }
  }
  
  event message_t* ReadBaconTlvCmdReceive.receive(message_t* msg_, 
      void* payload,
      uint8_t len){
    currentCommandType = call AMPacket.type(msg_);
    if (cmdMsg != NULL){
      printf("RX: ReadBaconTlv");
      printf(" BUSY!\n");
      printfflush();
      return msg_;
    }else{
      if ((call Pool.size()) >= 2){
        message_t* ret = call Pool.get();
        responseMsg = call Pool.get();
        cmdMsg = msg_;
        post loadTLVStorage();
        return ret;
      }else{
        printf("RX: ReadBaconTlv");
        printf(" Pool Empty!\n");
        printfflush();
        return msg_;
      }
    }
  }

  task void respondReadBaconTlv(){
    error_t err;
    read_bacon_tlv_response_msg_t* responsePl = (read_bacon_tlv_response_msg_t*)(call Packet.getPayload(responseMsg, sizeof(read_bacon_tlv_response_msg_t)));
    memcpy(&(responsePl->tlvs), tlvs, BACON_TLV_LEN);
    responsePl->error = SUCCESS;
    err = call ReadBaconTlvResponseSend.send(0, responseMsg, sizeof(read_bacon_tlv_response_msg_t));
  }

  event void ReadBaconTlvResponseSend.sendDone(message_t* msg, 
      error_t error){
    cleanup();
  }
  
  
  event message_t* WriteBaconTlvCmdReceive.receive(message_t* msg_, 
      void* payload,
      uint8_t len){
    currentCommandType = call AMPacket.type(msg_);
    if (cmdMsg != NULL){
      printf("RX: WriteBaconTlv");
      printf(" BUSY!\n");
      printfflush();
      return msg_;
    }else{
      if ((call Pool.size()) >= 2){
        message_t* ret = call Pool.get();
        responseMsg = call Pool.get();
        cmdMsg = msg_;
        post respondWriteBaconTlv();
        return ret;
      }else{
        printf("RX: WriteBaconTlv");
        printf(" Pool Empty!\n");
        printfflush();
        return msg_;
      }
    }
  }

  task void respondWriteBaconTlv(){
    write_bacon_tlv_cmd_msg_t* commandPl = (write_bacon_tlv_cmd_msg_t*)(call Packet.getPayload(cmdMsg, sizeof(write_bacon_tlv_cmd_msg_t)));
    error_t error = SUCCESS;
    tlv_entry_t* e;
    memcpy(tlvs, commandPl->tlvs, BACON_TLV_LEN);
    //verify that there is a TAG_VERSION in here somewhere: otherwise,
    //bacon will reject it.
    if (0 == call TLVUtils.findEntry(TAG_VERSION, 0, &e, tlvs)){
      error = EINVAL;
    }else{
      error = persistTLVStorage(tlvs);
    }
    if (error != SUCCESS){
      write_bacon_tlv_response_msg_t* responsePl = (write_bacon_tlv_response_msg_t*)(call Packet.getPayload(responseMsg, sizeof(write_bacon_tlv_response_msg_t)));
      responsePl->error = error;
      call WriteBaconTlvResponseSend.send(0, responseMsg, sizeof(write_bacon_tlv_response_msg_t));
    }
  }

  event void WriteBaconTlvResponseSend.sendDone(message_t* msg, 
      error_t error){
    cleanup();
  }

  message_t* tlvSetup(message_t* msg_){
    if (cmdMsg != NULL){
      printf("RX: %x BUSY!\n", currentCommandType);
      printfflush();
      return msg_;
    }else{
      currentCommandType = call AMPacket.type(msg_);
      if ((call Pool.size()) >= 2){
        message_t* ret = call Pool.get();
        responseMsg = call Pool.get();
        cmdMsg = msg_;
        post loadTLVStorage();
        return ret;
      }else{
        printf("RX: %x Pool empty!\n", currentCommandType);
        printfflush();
        return msg_;
      }
    }
  }

  event message_t* DeleteBaconTlvEntryCmdReceive.receive(message_t* msg_, 
      void* payload,
      uint8_t len){
    return tlvSetup(msg_);
  }

  task void respondDeleteBaconTlvEntry(){
    delete_bacon_tlv_entry_cmd_msg_t* commandPl = (delete_bacon_tlv_entry_cmd_msg_t*)(call Packet.getPayload(cmdMsg, sizeof(delete_bacon_tlv_entry_cmd_msg_t)));
    tlv_entry_t* e;
    uint8_t offset = call TLVUtils.findEntry(commandPl->tag, 0, &e,
      tlvs);
    error_t error = SUCCESS;
    if (offset == 0){
      error = EINVAL;
    }else{
      error = call TLVUtils.deleteEntry(offset, tlvs);
      if (error == SUCCESS){
        error = persistTLVStorage(tlvs);
      }
    }

    if (error != SUCCESS){
      delete_bacon_tlv_entry_response_msg_t* responsePl = (delete_bacon_tlv_entry_response_msg_t*)(call Packet.getPayload(responseMsg, sizeof(delete_bacon_tlv_entry_response_msg_t)));
      responsePl->error = EINVAL;
      call DeleteBaconTlvEntryResponseSend.send(0, responseMsg, sizeof(delete_bacon_tlv_entry_response_msg_t));
    }
  }

  event void DeleteBaconTlvEntryResponseSend.sendDone(message_t* msg, 
      error_t error){
    cleanup();
  }

  event message_t* AddBaconTlvEntryCmdReceive.receive(message_t* msg_, 
      void* payload,
      uint8_t len){
    return tlvSetup(msg_);
  }

  task void respondAddBaconTlvEntry(){
    add_bacon_tlv_entry_cmd_msg_t* commandPl = (add_bacon_tlv_entry_cmd_msg_t*)(call Packet.getPayload(cmdMsg, sizeof(add_bacon_tlv_entry_cmd_msg_t)));
    error_t err = SUCCESS;
    //add tag and initialize from commandPl
    uint8_t offset;
    printf("AddEntry %x %u %p %p %u\n", commandPl->tag, commandPl->len,
      (tlv_entry_t*)commandPl, tlvs, 0);
    printfflush();
    offset = call TLVUtils.addEntry(commandPl->tag, commandPl->len,
      (tlv_entry_t*)commandPl, tlvs, 0);
    printf("Offset: %u\n", offset);
    printfflush();
    if (offset == 0){
      err = ESIZE;
    } else {
      err = persistTLVStorage(tlvs);
    }

    if (err != SUCCESS){
      add_bacon_tlv_entry_response_msg_t* responsePl = (add_bacon_tlv_entry_response_msg_t*)(call Packet.getPayload(responseMsg, sizeof(add_bacon_tlv_entry_response_msg_t)));
      responsePl->error = ESIZE;
      switch(commandPl->tag){
        case TAG_VERSION:
          call WriteBaconVersionResponseSend.send(0, responseMsg, sizeof(add_bacon_tlv_entry_response_msg_t));
          break;
        case TAG_GLOBAL_ID:
          call WriteBaconBarcodeIdResponseSend.send(0, responseMsg, sizeof(add_bacon_tlv_entry_response_msg_t));
          break;
        default:
          call AddBaconTlvEntryResponseSend.send(0, responseMsg, sizeof(add_bacon_tlv_entry_response_msg_t));
          break;
      }
    }
  }

  event void AddBaconTlvEntryResponseSend.sendDone(message_t* msg, 
      error_t error){
    cleanup();
  }

  event message_t* ReadBaconTlvEntryCmdReceive.receive(message_t* msg_, 
      void* payload,
      uint8_t len){
    return tlvSetup(msg_);
  }

  task void respondReadBaconTlvEntry(){
    read_bacon_tlv_entry_cmd_msg_t* commandPl = (read_bacon_tlv_entry_cmd_msg_t*)(call Packet.getPayload(cmdMsg, sizeof(read_bacon_tlv_entry_cmd_msg_t)));
    read_bacon_tlv_entry_response_msg_t* responsePl = (read_bacon_tlv_entry_response_msg_t*)(call Packet.getPayload(responseMsg, sizeof(read_bacon_tlv_entry_response_msg_t)));
    tlv_entry_t* entry;
    uint8_t initOffset = 0;
    uint8_t offset = call TLVUtils.findEntry(commandPl->tag, 
      initOffset, &entry, tlvs);
    if (0 == offset){
      responsePl->error = EINVAL;
    } else{
      memcpy((void*)(&responsePl->tag), (void*)entry, entry->len+2);
      responsePl->error = SUCCESS;
    }
    switch(commandPl->tag){
      case TAG_VERSION:
        call ReadBaconVersionResponseSend.send(0, responseMsg, 
          sizeof(read_bacon_version_response_msg_t));
        break;
      case TAG_GLOBAL_ID:
        call ReadBaconBarcodeIdResponseSend.send(0, responseMsg, 
          sizeof(read_bacon_barcode_id_response_msg_t));
        break;
      default:
        call ReadBaconTlvEntryResponseSend.send(0, responseMsg, sizeof(read_bacon_tlv_entry_response_msg_t));
        break;
    }
  }

  event void ReadBaconTlvEntryResponseSend.sendDone(message_t* msg, 
      error_t error){
    cleanup();
  }

  event void ReadBaconVersionResponseSend.sendDone(message_t* msg, 
      error_t error){
    cleanup();
  }
  event void ReadBaconBarcodeIdResponseSend.sendDone(message_t* msg, 
      error_t error){
    cleanup();
  }

  event void WriteBaconBarcodeIdResponseSend.sendDone(message_t* msg, 
      error_t error){
    cleanup();
  }
  event void WriteBaconVersionResponseSend.sendDone(message_t* msg, 
      error_t error){
    cleanup();
  }

}
