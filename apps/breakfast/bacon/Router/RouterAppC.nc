 #include "StorageVolumes.h"
 #include "message.h"
 #include "CXDebug.h"
 #include "router.h"
configuration RouterAppC{
} implementation {
  #if ENABLE_PRINTF == 1
  #if RAW_SERIAL_PRINTF == 1
  components SerialPrintfC;
  #else
  components SerialStartC;
  components PrintfC;
  #endif
  #endif

  components WatchDogC;
  #ifndef NO_STACKGUARD
  components StackGuardMilliC;
  #endif

  components MainC;
  components RouterP;
  components ActiveMessageC;

  
  #ifndef ENABLE_AUTOPUSH
  #define ENABLE_AUTOPUSH 1
  #endif

  #if ENABLE_AUTOPUSH == 1
  components new RecordPushRequestC(VOLUME_RECORD, TRUE);
  components new RouterAMSenderC(AM_LOG_RECORD_DATA_MSG);
  components CXLinkPacketC;

  RecordPushRequestC.Pool -> ActiveMessageC;
  RecordPushRequestC.AMSend -> RouterAMSenderC;
  RecordPushRequestC.Packet -> RouterAMSenderC;
  RecordPushRequestC.CXLinkPacket -> CXLinkPacketC;

  components SlotSchedulerC;
  SlotSchedulerC.PushCookie -> RecordPushRequestC.PushCookie;
  SlotSchedulerC.WriteCookie -> RecordPushRequestC.WriteCookie;
  #else
  #warning "Disable autopush"
  #endif

  #ifndef ENABLE_SETTINGS_CONFIG
  #define ENABLE_SETTINGS_CONFIG 1
  #endif

  #if ENABLE_SETTINGS_CONFIG == 1
  components SettingsStorageConfiguratorC;
  SettingsStorageConfiguratorC.Pool -> ActiveMessageC;
  #else
  #warning SettingsStorageConfigurator disabled!
  #endif

  components SettingsStorageC;

  #ifndef ENABLE_SETTINGS_LOGGING
  #define ENABLE_SETTINGS_LOGGING 1
  #endif

  #if ENABLE_SETTINGS_LOGGING == 1
  components new LogStorageC(VOLUME_RECORD, TRUE) as SettingsLS;
  SettingsStorageC.LogWrite -> SettingsLS;
  #else
  #warning Disabled settings logging!
  components new DummyLogWriteC();
  SettingsStorageC.LogWrite -> DummyLogWriteC;
  #endif
  
  #if ENABLE_AUTOPUSH == 1
  RecordPushRequestC.Get -> CXRouterC.Get[NS_ROUTER];
  #endif

  RouterP.SplitControl -> ActiveMessageC;
  RouterP.Boot -> MainC;

  components new AMReceiverC(AM_LOG_RECORD_DATA_MSG);
  RouterP.ReceiveData -> AMReceiverC;
  RouterP.AMPacket -> AMReceiverC;

  components new LogStorageC(VOLUME_RECORD, TRUE);
  RouterP.LogWrite -> LogStorageC;
  RouterP.Pool -> ActiveMessageC;

  components CXRouterC;
  components new TimerMilliC();
  RouterP.CXDownload -> CXRouterC.CXDownload[NS_SUBNETWORK];
  RouterP.SettingsStorage -> SettingsStorageC;
  RouterP.Timer -> TimerMilliC;

  components new LogStorageC(VOLUME_RECORD, TRUE) 
    as NetworkMembershipLS;
  CXRouterC.LogWrite -> NetworkMembershipLS;

  #ifndef PHOENIX_LOGGING
  #define PHOENIX_LOGGING 1
  #endif

  #if PHOENIX_LOGGING == 1
  //yeesh this is ugly
  components PhoenixNeighborhoodP;
  components new LogStorageC(VOLUME_RECORD, TRUE) as PhoenixLS;
  PhoenixNeighborhoodP.LogWrite -> PhoenixLS;
  #else
  #warning Phoenix disabled!
  #endif

  #ifndef ENABLE_AUTOSENDER
  #define ENABLE_AUTOSENDER 0
  #endif
  #if ENABLE_AUTOSENDER == 1
  #warning Enabled auto-sender: TEST ONLY
  components AutoSenderC;
  #endif

  #ifndef ENABLE_TESTBED
  #define ENABLE_TESTBED 0
  #endif
  #if ENABLE_TESTBED == 1
  #warning Enable Testbed Router
  components TestbedRouterC;
  #endif


  components new AMReceiverC(AM_CX_DOWNLOAD) as CXDownloadReceive;
  RouterP.CXDownloadReceive -> CXDownloadReceive; 

}
