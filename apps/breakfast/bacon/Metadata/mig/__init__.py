#!/usr/bin/env python

##generated with: 
## grep 'msg{' ctrl_messages.h | awk '{print $3}' | tr -d '{' | sed -re 's,(_|^)([a-z]),\u\2,g'
allS='''ReadIvCmdMsg
ReadIvResponseMsg
ReadMfrIdCmdMsg
ReadMfrIdResponseMsg
ReadBaconBarcodeIdCmdMsg
ReadBaconBarcodeIdResponseMsg
WriteBaconBarcodeIdCmdMsg
WriteBaconBarcodeIdResponseMsg
ScanBusCmdMsg
ScanBusResponseMsg
PingCmdMsg
PingResponseMsg
ResetBaconCmdMsg
ResetBaconResponseMsg
SetBusPowerCmdMsg
SetBusPowerResponseMsg
ReadBaconTlvCmdMsg
ReadBaconTlvResponseMsg
WriteBaconTlvCmdMsg
WriteBaconTlvResponseMsg
DeleteBaconTlvEntryCmdMsg
DeleteBaconTlvEntryResponseMsg
AddBaconTlvEntryCmdMsg
AddBaconTlvEntryResponseMsg
ReadBaconTlvEntryCmdMsg
ReadBaconTlvEntryResponseMsg
ReadToastTlvCmdMsg
ReadToastTlvResponseMsg
WriteToastTlvCmdMsg
WriteToastTlvResponseMsg
DeleteToastTlvEntryCmdMsg
DeleteToastTlvEntryResponseMsg
AddToastTlvEntryCmdMsg
AddToastTlvEntryResponseMsg
ReadToastTlvEntryCmdMsg
ReadToastTlvEntryResponseMsg
ReadToastBarcodeIdCmdMsg
ReadToastBarcodeIdResponseMsg
WriteToastBarcodeIdCmdMsg
WriteToastBarcodeIdResponseMsg
ReadToastAssignmentsCmdMsg
ReadToastAssignmentsResponseMsg
WriteToastAssignmentsCmdMsg
WriteToastAssignmentsResponseMsg
ReadToastAssignmentsCmdMsg
ReadToastAssignmentsResponseMsg
ReadToastVersionCmdMsg
ReadToastVersionResponseMsg
WriteToastVersionCmdMsg
WriteToastVersionResponseMsg
ReadBaconVersionCmdMsg
ReadBaconVersionResponseMsg
WriteBaconVersionCmdMsg
WriteBaconVersionResponseMsg
'''

__all__= ['PrintfMsg'] + allS.split()