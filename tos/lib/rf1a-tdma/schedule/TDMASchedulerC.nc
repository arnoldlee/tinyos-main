configuration TDMASchedulerC {
  provides interface TDMARoutingSchedule;

  uses interface TDMAPhySchedule;
  uses interface FrameStarted;
  provides interface SplitControl;
  uses interface SplitControl as SubSplitControl;
  provides interface SlotStarted;
  provides interface ScheduledSend as DefaultScheduledSend;
  
} implementation {
  #if TDMA_ROOT == 1 
  components RouterSchedulerC as TDMASchedulerP;
  #else 
  components LeafSchedulerC as TDMASchedulerP;
  #endif

  TDMARoutingSchedule = TDMASchedulerP.TDMARoutingSchedule;
  TDMAPhySchedule = TDMASchedulerP.TDMAPhySchedule;
  FrameStarted = TDMASchedulerP.FrameStarted;
  SplitControl = TDMASchedulerP.SplitControl;
  TDMASchedulerP.SubSplitControl = SubSplitControl;
  SlotStarted = TDMASchedulerP.SlotStarted;
  DefaultScheduledSend = TDMASchedulerP.DefaultScheduledSend;
}