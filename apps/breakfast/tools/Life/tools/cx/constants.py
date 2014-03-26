#!/usr/bin/env python

# Copyright (c) 2014 Johns Hopkins University
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# - Redistributions of source code must retain the above copyright
#   notice, this list of conditions and the following disclaimer.
# - Redistributions in binary form must reproduce the above copyright
#   notice, this list of conditions and the following disclaimer in the
#   documentation and/or other materials provided with the
#   distribution.
# - Neither the name of the copyright holders nor the names of
#   its contributors may be used to endorse or promote products derived
#   from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL
# THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
# INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
# OF THE POSSIBILITY OF SUCH DAMAGE.

SS_KEY_GLOBAL_ID=0x04
SS_KEY_LOW_PUSH_THRESHOLD=0x10 #(uint8_t)
SS_KEY_HIGH_PUSH_THRESHOLD=0x11 #(uint8_t)
SS_KEY_TOAST_SAMPLE_INTERVAL=0x12 #(uint32_t)
SS_KEY_REBOOT_COUNTER=0x13 #(uint16_t)
SS_KEY_BACON_SAMPLE_INTERVAL=0x14 #(uint32_t)
SS_KEY_PROBE_SCHEDULE=0x15 #(probe_schedule_t) (CXMac.h)
SS_KEY_PHOENIX_SAMPLE_INTERVAL=0x16 #(uint32_t) (phoenix.h)
SS_KEY_PHOENIX_TARGET_REFS=0x17 #(uint32_t) (phoenix.h)
SS_KEY_DOWNLOAD_INTERVAL=0x18   #(uint32_t) (router.h)
SS_KEY_MAX_DOWNLOAD_ROUNDS=0x19 #(uint8_t)
SS_KEY_TIME_SYNC=0x20 #(uint32_t)


DEFAULT_SAMPLE_INTERVAL=(60*1024*10)

NS_GLOBAL=0
NS_SUBNETWORK=1
NS_ROUTER=2

ROLE_LEAF = 0
ROLE_ROUTER = 1
ROLE_BASESTATION = 2

CHANNEL_GLOBAL=128
CHANNEL_ROUTER=64
CHANNEL_SUBNETWORK_DEFAULT=0

DEFAULT_PROBE_INTERVAL=1024
SEGMENT_MAX_DEPTH=5

MAX_REQUEST_UNIT=50000
DEFAULT_RADIO_CONFIG = {
  'probeInterval': DEFAULT_PROBE_INTERVAL,
  'globalChannel': CHANNEL_GLOBAL,
  'subNetworkChannel': CHANNEL_SUBNETWORK_DEFAULT,
  'routerChannel': CHANNEL_ROUTER,
  'globalInvFrequency': 1,
  'subNetworkInvFrequency': 1,
  'routerInvFrequency': 1,
  'globalBW': 2,
  'subNetworkBW': 2,
  'routerBW': 2,
  'globalMaxDepth':2*SEGMENT_MAX_DEPTH,
  'subNetworkMaxDepth':SEGMENT_MAX_DEPTH,
  'routerMaxDepth':SEGMENT_MAX_DEPTH,
  'maxDownloadRounds':10}
BCAST_ADDR= 0xFFFF

MAX_RECOVERY_ATTEMPTS=2
