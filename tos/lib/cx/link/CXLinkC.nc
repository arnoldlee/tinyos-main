
 #include "CXLink.h"
configuration CXLinkC {
  provides interface SplitControl;
  provides interface CXRequestQueue;
  //for debug only
  provides interface Rf1aStatus;
} implementation {
  components CXLinkP;

  components GDO1CaptureC;
  components new AlarmMicro32C() as TransmitAlarm;
  components new Timer32khzC() as FrameTimer;
  CXLinkP.TransmitAlarm -> TransmitAlarm;
  CXLinkP.FrameTimer -> FrameTimer;
  CXLinkP.SynchCapture -> GDO1CaptureC;

  components new Rf1aPhysicalC();
  CXLinkP.Rf1aPhysical -> Rf1aPhysicalC;
  CXLinkP.Rf1aPhysicalMetadata -> Rf1aPhysicalC;
  CXLinkP.DelayedSend -> Rf1aPhysicalC;
  CXLinkP.Resource -> Rf1aPhysicalC;

  components new PoolC(cx_request_t, REQUEST_QUEUE_LEN);
  components new PriorityQueueC(cx_request_t*, REQUEST_QUEUE_LEN);
  CXLinkP.Pool -> PoolC;
  CXLinkP.Queue -> PriorityQueueC;
  PriorityQueueC.Compare -> CXLinkP;

  SplitControl = CXLinkP;
  CXRequestQueue = CXLinkP;

  //for debug only
  Rf1aStatus = Rf1aPhysicalC;
}