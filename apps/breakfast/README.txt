This document contains a guide to the contents of the apps/breakfast
directory as well as notes on several important ID spaces in use:
record types, AM ID's, and storage settings keys. Please keep this
up-to-date as new ID's are added.

Directory contents
==================
This contains essentially all code for the breakfast suite of hardware
that is not either part of the platform definition, part of the build
process, or the CX networking stack.

Active code
-----------
Sensorbed : Testbed server, build notes, and testbed-compatible BSL. 

bacon : Main bacon applications (Leaf, Router, and BaseStation),
  sub-applications, and a ton of obsolete test code used during the
  development process.

logic-cli : command line tool for use with the Saleae Logic analyzer.
  Useful for automating collection of long traces.

toast : Main toast application, scripts and binaries for
  manufacture-time installation of firmware, tests for
  sub-applications.

tools : Python user interface scripts for interacting with the
  breakfast hardware.

util : breakfast-to-toast I2C communication code, bacon/toast barcode
  access functions, utility for detecting stack overruns, debug
  utilities, testbed scripts. 


Unused/obsolete code
--------------------
electrical_tests : binaries and installers for testing specific steps
  that had the potential to cause electrical issues on the breakfast
  hardware

independent : test code for applications that could run on both
  bacon/toast

pde_fw : binaries and loader scripts for single-purpose firmware used
  to test current draw and behavior during the hardware design
  process.

timing : test code for determining how long it takes to start/stop the
  radio driver and perform a send.

minSerial.py : test code to check basic operation of serial
  communication without involving the whole python serial stack.



Some Collected Caveats
======================
(Marked n.b. or N.B. in source)

- When using FEC, the packet may be padded with an additional 0x00
  byte when transmitted: this is due to the fact that the CRC module
  operates on 16-bit chunks of data.  Note that the sender will not
  see this, otherwise setPayloadLength() and getPayloadLength() would
  return different values depending on whether the ultimate packet
  length was odd or even. 
- as a potential FEC-related issue, I've observed that a packet length
  of 69 caused synch issues (original + forwarder were out of step
  by 2-4 uS at 1st retx), while a length of 68 or 70 were OK (this
  is length prior to applying FEC). I don't know why this could happen: the
  packets being sent take the same amount of time, so I don't think
  there's a problem with the padding process. I verified that with FEC
  off, a 69-byte payload was fine. 

AM ID's in common use:
======================
0xC0 - 0xC8 in use, 0xC9-0xCF reserved
--------------
bacon/settingsStorage/SettingsStorage.h: AM_SET_SETTINGS_STORAGE_MSG = 0xC0,
bacon/settingsStorage/SettingsStorage.h: AM_GET_SETTINGS_STORAGE_CMD_MSG = 0xC1,
bacon/settingsStorage/SettingsStorage.h: AM_GET_SETTINGS_STORAGE_RESPONSE_MSG = 0xC2,
bacon/settingsStorage/SettingsStorage.h: AM_CLEAR_SETTINGS_STORAGE_MSG = 0xC3,
lib/cx/scheduler/CXScheduler.h: AM_CX_SCHEDULE_MSG= 0xC4
lib/cx/scheduler/CXScheduler.h: AM_CX_ASSIGNMENT_MSG= 0xC5
lib/cxl/mac/CXMac.h: AM_WAKEUP = 0xC6
lib/cxl/mac/CXMac.h: AM_SLEEP = 0xC7
lib/cxl/mac/CXMac.h: AM_CTS = 0xC8

CX basestation control 
0xD0 - 0xD5 in use, 0xD6 - 0xDF reserved
---------------
bacon/Basestation/basestation.h: AM_CX_DOWNLOAD=0xD0
bacon/Basestation/basestation.h: AM_CX_DOWNLOAD_FINISHED=0xD1
bacon/Basestation/basestation.h: AM_CTRL_ACK=0xD2
bacon/Basestation/basestation.h: AM_STATUS_TIME_REF=0xD3
bacon/Basestation/basestation.h: AM_IDENTIFY_REQUEST=0xD4
bacon/Basestation/basestation.h: AM_IDENTIFY_RESPONSE=0xD5

Metadata: 0x80 - 0xB1 in use, 0xB2-0xBF reserved
--------
bacon/Metadata/ctrl_messages.h:  AM_READ_IV_CMD_MSG = 0x80,
bacon/Metadata/ctrl_messages.h:  AM_READ_IV_RESPONSE_MSG = 0x81,
bacon/Metadata/ctrl_messages.h:  AM_READ_MFR_ID_CMD_MSG = 0x82,
bacon/Metadata/ctrl_messages.h:  AM_READ_MFR_ID_RESPONSE_MSG = 0x83,
bacon/Metadata/ctrl_messages.h:  AM_READ_BACON_BARCODE_ID_CMD_MSG = 0xAA,
bacon/Metadata/ctrl_messages.h:  AM_READ_BACON_BARCODE_ID_RESPONSE_MSG = 0x85,
bacon/Metadata/ctrl_messages.h:  AM_WRITE_BACON_BARCODE_ID_CMD_MSG = 0xA4,
bacon/Metadata/ctrl_messages.h:  AM_WRITE_BACON_BARCODE_ID_RESPONSE_MSG = 0x87,
bacon/Metadata/ctrl_messages.h:  AM_WRITE_BACON_VERSION_CMD_MSG = 0xA4,
bacon/Metadata/ctrl_messages.h:  AM_WRITE_BACON_VERSION_RESPONSE_MSG = 0xAE,
bacon/Metadata/ctrl_messages.h:  AM_READ_BACON_VERSION_CMD_MSG = 0xAA,
bacon/Metadata/ctrl_messages.h:  AM_READ_BACON_VERSION_RESPONSE_MSG = 0xAF,
bacon/Metadata/ctrl_messages.h:  AM_READ_TOAST_BARCODE_ID_CMD_MSG = 0xA8,
bacon/Metadata/ctrl_messages.h:  AM_READ_TOAST_BARCODE_ID_RESPONSE_MSG = 0x89,
bacon/Metadata/ctrl_messages.h:  AM_WRITE_TOAST_BARCODE_ID_CMD_MSG = 0xA6,
bacon/Metadata/ctrl_messages.h:  AM_WRITE_TOAST_BARCODE_ID_RESPONSE_MSG = 0x8B,
bacon/Metadata/ctrl_messages.h:  AM_READ_TOAST_ASSIGNMENTS_CMD_MSG = 0xA8,
bacon/Metadata/ctrl_messages.h:  AM_READ_TOAST_ASSIGNMENTS_RESPONSE_MSG = 0x8D,
bacon/Metadata/ctrl_messages.h:  AM_WRITE_TOAST_ASSIGNMENTS_CMD_MSG = 0xA6,
bacon/Metadata/ctrl_messages.h:  AM_WRITE_TOAST_ASSIGNMENTS_RESPONSE_MSG = 0x8F,
bacon/Metadata/ctrl_messages.h:  AM_WRITE_TOAST_VERSION_CMD_MSG = 0xA6,
bacon/Metadata/ctrl_messages.h:  AM_WRITE_TOAST_VERSION_RESPONSE_MSG = 0xAC,
bacon/Metadata/ctrl_messages.h:  AM_READ_TOAST_VERSION_CMD_MSG = 0xA8,
bacon/Metadata/ctrl_messages.h:  AM_READ_TOAST_VERSION_RESPONSE_MSG = 0xAD,
bacon/Metadata/ctrl_messages.h:  AM_READ_ANALOG_SENSOR_CMD_MSG = 0xB0,
bacon/Metadata/ctrl_messages.h:  AM_READ_ANALOG_SENSOR_RESPONSE_MSG = 0xB1,
bacon/Metadata/ctrl_messages.h:  AM_SCAN_BUS_CMD_MSG = 0x90,
bacon/Metadata/ctrl_messages.h:  AM_SCAN_BUS_RESPONSE_MSG = 0x91,
bacon/Metadata/ctrl_messages.h:  AM_PING_CMD_MSG = 0x92,
bacon/Metadata/ctrl_messages.h:  AM_PING_RESPONSE_MSG = 0x93,
bacon/Metadata/ctrl_messages.h:  AM_RESET_BACON_CMD_MSG = 0x94,
bacon/Metadata/ctrl_messages.h:  AM_RESET_BACON_RESPONSE_MSG = 0x95,
bacon/Metadata/ctrl_messages.h:  AM_SET_BUS_POWER_CMD_MSG = 0x96,
bacon/Metadata/ctrl_messages.h:  AM_SET_BUS_POWER_RESPONSE_MSG = 0x97,
bacon/Metadata/ctrl_messages.h:  AM_READ_BACON_TLV_CMD_MSG = 0x98,
bacon/Metadata/ctrl_messages.h:  AM_READ_BACON_TLV_RESPONSE_MSG = 0x99,
bacon/Metadata/ctrl_messages.h:  AM_READ_TOAST_TLV_CMD_MSG = 0x9A,
bacon/Metadata/ctrl_messages.h:  AM_READ_TOAST_TLV_RESPONSE_MSG = 0x9B,
bacon/Metadata/ctrl_messages.h:  AM_WRITE_BACON_TLV_CMD_MSG = 0x9C,
bacon/Metadata/ctrl_messages.h:  AM_WRITE_BACON_TLV_RESPONSE_MSG = 0x9D,
bacon/Metadata/ctrl_messages.h:  AM_WRITE_TOAST_TLV_CMD_MSG = 0x9E,
bacon/Metadata/ctrl_messages.h:  AM_WRITE_TOAST_TLV_RESPONSE_MSG = 0x9F,
bacon/Metadata/ctrl_messages.h:  AM_DELETE_BACON_TLV_ENTRY_CMD_MSG = 0xA0,
bacon/Metadata/ctrl_messages.h:  AM_DELETE_BACON_TLV_ENTRY_RESPONSE_MSG = 0xA1,
bacon/Metadata/ctrl_messages.h:  AM_DELETE_TOAST_TLV_ENTRY_CMD_MSG = 0xA2,
bacon/Metadata/ctrl_messages.h:  AM_DELETE_TOAST_TLV_ENTRY_RESPONSE_MSG = 0xA3,
bacon/Metadata/ctrl_messages.h:  AM_ADD_BACON_TLV_ENTRY_CMD_MSG = 0xA4,
bacon/Metadata/ctrl_messages.h:  AM_ADD_BACON_TLV_ENTRY_RESPONSE_MSG = 0xA5,
bacon/Metadata/ctrl_messages.h:  AM_ADD_TOAST_TLV_ENTRY_CMD_MSG = 0xA6,
bacon/Metadata/ctrl_messages.h:  AM_READ_TOAST_TLV_ENTRY_RESPONSE_MSG = 0xA9,
bacon/Metadata/ctrl_messages.h:  AM_READ_BACON_TLV_ENTRY_CMD_MSG = 0xAA,
bacon/Metadata/ctrl_messages.h:  AM_READ_BACON_TLV_ENTRY_RESPONSE_MSG = 0xAB,
bacon/Metadata/ctrl_messages.h:  AM_READ_BACON_SENSOR_CMD_MSG = 0xB2,
bacon/Metadata/ctrl_messages.h:  AM_READ_BACON_SENSOR_RESPONSE_MSG = 0xB3,

Misc. Tests: 0xD0 - 0xDF
---------
bacon/cxActiveMessage/test.h:#define AM_ID_CX_TESTBED 0xdc
bacon/cxlTestbed/autosender.h:  AM_TEST_MSG=0xdc,


serial port logging 
-------
$(TOSDIR)/lib/printf/printf.h: AM_PRINTF_MSG = 100, //0x64
lib/cxl/scheduler/AMStatsLog.h: AM_STATS_LOG_RADIO = 0xFA
lib/cxl/scheduler/AMStatsLog.h: AM_STATS_LOG_RX = 0xFB
lib/cxl/scheduler/AMStatsLog.h: AM_STATS_LOG_TX = 0xFC

Log Records: 0xE0 - 0xEF
-------
tos/platforms/bacon/chips/stm25p/RecordStorage.h: AM_LOG_RECORD_DATA_MSG = 0xE0


CX collection control: 0xF0 - 0xF7
------
bacon/autoPush/RecordRequest.h: AM_CX_RECORD_REQUEST_MSG = 0xF0

Ping: 0xF8-0xF9
------
bacon/ping/ping.h: AM_PING_MSG=0xF8
bacon/ping/ping.h: AM_PONG_MSG=0xF9

Unused : 0xFD-0xFF
------

Log record types
==============
ToastSampler.h: RECORD_TYPE_TOAST_DISCONNECTED 0x10
ToastSampler.h: RECORD_TYPE_TOAST_CONNECTED 0x11
ToastSampler.h: RECORD_TYPE_SAMPLE 0x12
ToastSampler.h: RECORD_TYPE_SAMPLE_LONG 0x13
BaconSampler.h: RECORD_TYPE_BACON_SAMPLE 0x14
router.h: RECORD_TYPE_TUNNELED 0x15
phoenix.h: RECORD_TYPE_PHOENIX 0x16
SettingsStorage.h: RECORD_TYPE_SETTINGS 0x17
LogPrintf.h: RECORD_TYPE_LOG_PRINTF 0x18
networkMembership.h: RECORD_TYPE_NETWORK_MEMBERSHIP 0x19

TLV Tags
=========
metadata.h: #define TAG_TOAST_ASSIGNMENTS (0x05)

SettingsStorage Keys
=========
SS_KEY_LOW_PUSH_THRESHOLD 0x10 (uint8_t)
SS_KEY_HIGH_PUSH_THRESHOLD 0x11 (uint8_t)
SS_KEY_TOAST_SAMPLE_INTERVAL 0x12 (uint32_t)
SS_KEY_REBOOT_COUNTER 0x13 (uint16_t)
SS_KEY_BACON_SAMPLE_INTERVAL 0x14 (uint32_t)
SS_KEY_PROBE_SCHEDULE 0x15 (probe_schedule_t) (CXMac.h)
SS_KEY_PHOENIX_SAMPLE_INTERVAL 0x16 (uint32_t) (phoenix.h)
SS_KEY_PHOENIX_TARGET_REFS 0x17 (uint8_t) (phoenix.h)
SS_KEY_DOWNLOAD_INTERVAL 0x18 (uint32_t) (router.h)
SS_KEY_MAX_DOWNLOAD_ROUNDS 0x19 (uint8_t)
SS_KEY_SERIAL_LOG_STORAGE_COOKIE 0x20 (storage_cookie_t)
SS_KEY_TIME_SYNC 0x21 (uint8_t)
