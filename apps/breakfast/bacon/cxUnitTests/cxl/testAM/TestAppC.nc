configuration TestAppC {
} implementation {
  components PlatformSerialC;
  components SerialPrintfC;

  components ActiveMessageC;
  components CXLppC;

  components TestP;
  components LedsC;

  TestP.SplitControl -> ActiveMessageC;

  components new AMSenderC(0xDC);
  components new AMReceiverC(0xDC);
  TestP.Receive -> AMReceiverC;
  TestP.AMSend -> AMSenderC;

  TestP.LppControl -> CXLppC;
  TestP.Leds -> LedsC;

  components MainC;
  TestP.Boot -> MainC;

  TestP.UartStream -> PlatformSerialC;
  TestP.SerialControl -> PlatformSerialC;
  TestP.Packet -> AMSenderC;

  TestP.Pool -> ActiveMessageC.Pool;
  
  #if CX_BASESTATION == 1
  components CXBasestationMacC;
  TestP.CXMacMaster -> CXBasestationMacC.CXMacMaster;
  #endif
}