
 #include "test.h"
configuration TestAppC {
} implementation {
  components PlatformSerialC;
  components SerialPrintfC;

  components ActiveMessageC;

  components TestP;
  components LedsC;

  TestP.SplitControl -> ActiveMessageC;

  components new GlobalAMSenderC(AM_TEST_PAYLOAD);
  components new SubNetworkAMSenderC(AM_TEST_PAYLOAD);
  components new RouterAMSenderC(AM_TEST_PAYLOAD);
  components new AMReceiverC(AM_TEST_PAYLOAD);
  TestP.Receive -> AMReceiverC;
  TestP.GlobalAMSend -> GlobalAMSenderC;
  TestP.SubNetworkAMSend -> SubNetworkAMSenderC;
  TestP.RouterAMSend -> RouterAMSenderC;

  TestP.Leds -> LedsC;

  components MainC;
  TestP.Boot -> MainC;

  TestP.UartStream -> PlatformSerialC;
  TestP.SerialControl -> PlatformSerialC;
  TestP.Packet -> GlobalAMSenderC;

  TestP.Pool -> ActiveMessageC.Pool;
  components PingC;
  PingC.Pool -> ActiveMessageC.Pool;

  #if CX_ROUTER == 1
  components CXRouterC;
  TestP.CXDownload -> CXRouterC.CXDownload;
  #endif
}
