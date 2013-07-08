configuration SlotSchedulerC{

  provides interface SplitControl;
  provides interface Send;
  provides interface Packet;
  provides interface Receive;

  uses interface Pool<message_t>;

  uses interface SlotController;

  provides interface Neighborhood;
} implementation {
  components CXWakeupC;
  components SlotSchedulerP;

  components new Timer32khzC() as SlotTimer;
  components new Timer32khzC() as FrameTimer;
  SlotSchedulerP.SlotTimer -> SlotTimer;
  SlotSchedulerP.FrameTimer -> FrameTimer;

  Send = SlotSchedulerP.Send;
  Receive = SlotSchedulerP.Receive;
  SplitControl = CXWakeupC.SplitControl;
  SlotSchedulerP.Pool = Pool;
  CXWakeupC.Pool = Pool;
  SlotSchedulerP.SlotController = SlotController;
  
  SlotSchedulerP.CXLink -> CXWakeupC.CXLink;
  SlotSchedulerP.LppControl -> CXWakeupC.LppControl;
  SlotSchedulerP.CXMacPacket -> CXWakeupC.CXMacPacket;
  SlotSchedulerP.CXLinkPacket -> CXWakeupC.CXLinkPacket;
  SlotSchedulerP.Packet -> CXWakeupC.Packet;
  SlotSchedulerP.SubSend -> CXWakeupC.Send;
  SlotSchedulerP.SubReceive -> CXWakeupC.Receive;

  components NeighborhoodC;
  SlotSchedulerP.Neighborhood -> NeighborhoodC;
  Neighborhood = NeighborhoodC;
  NeighborhoodC.LppProbeSniffer -> CXWakeupC;

  Packet = CXWakeupC.Packet;

  components CXAMAddressC;
  SlotSchedulerP.ActiveMessageAddress -> CXAMAddressC;

  components CXRoutingTableC;
  SlotSchedulerP.RoutingTable -> CXRoutingTableC;

}