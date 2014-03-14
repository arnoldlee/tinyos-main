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

from tinyos.message.MoteIF import MoteIF
import Queue 
import time

from tools.labeler.TOS import TOS
from tools.cx.listeners.CtrlAckListener import CtrlAckListener
from tools.cx.messages.CtrlAck import CtrlAck

from tools.cx.listeners.CxDownloadFinishedListener import CxDownloadFinishedListener
from tools.cx.listeners.IdentifyResponseListener import IdentifyResponseListener
from tools.cx.messages.FwdStatus import FwdStatus
from tools.cx.listeners.FwdStatusListener import FwdStatusListener
from tools.cx.listeners.CxEosReportListener import CxEosReportListener
from tools.cx.messages.IdentifyResponse import IdentifyResponse
from tools.cx.messages.IdentifyRequest import IdentifyRequest
from tools.cx.messages.CxDownloadFinished import CxDownloadFinished
from tools.cx.messages import SetProbeSchedule
from tools.cx.messages import SetMaxDownloadRounds
from tools.cx.messages import CxDownload
from tools.cx.messages import CxEosReport

import tools.cx.constants as constants

from threading import Thread

class MultipleSourceException(Exception):
    pass

class CXMoteIF(MoteIF):
    def __init__(self):
        MoteIF.__init__(self)
        self.txQueue = Queue.Queue()
        self.ackQueue = Queue.Queue()
        self.addListener(CtrlAckListener(self.ackQueue),
          CtrlAck)
        self.fwdStatusListener = FwdStatusListener()
        self.addListener(self.fwdStatusListener, FwdStatus)
        self.finishedListener = CxDownloadFinishedListener()
        self.addListener(self.finishedListener, CxDownloadFinished)

        self.identifyResponseListener = IdentifyResponseListener()
        self.addListener(self.identifyResponseListener,
          IdentifyResponse)

        self.eosQueue = Queue.Queue()
        self.eosListener =  CxEosReportListener(self.eosQueue)
        self.addListener(self.eosListener, CxEosReport.CxEosReport)

        self.fwdStatusTimeout = 60
        self.source = None
        self.sendWorkerThread = Thread(target=self.sendWorker,
          name="sendWorker")
        self.sendWorkerThread.daemon = True
        self.sendWorkerThread.start()


    def identifyMote(self):
        identifyRequestMsg = IdentifyRequest()
        with self.identifyResponseListener.identifiedCV:
            self.sendMsg(self.source, 
              constants.BCAST_ADDR,
              identifyRequestMsg.get_amType(),
              0,
              identifyRequestMsg)
            self.identifyResponseListener.identifiedCV.wait(1)
        self.bsId = self.identifyResponseListener.moteId
        return self.bsId != constants.BCAST_ADDR
        

    def configureMoteRadio(self, moteId, config):
        radioConfig = constants.DEFAULT_RADIO_CONFIG.copy()
        radioConfig.update(config)
        #set up probe schedule appropriately
        setProbeScheduleMsg = SetProbeSchedule.SetProbeSchedule(
          radioConfig['probeInterval'],
          [ radioConfig['globalChannel'], 
            radioConfig['subNetworkChannel'], 
            radioConfig['routerChannel']],
          [ radioConfig['globalInvFrequency'], 
            radioConfig['subNetworkInvFrequency'], 
            radioConfig['routerInvFrequency']],
          [ radioConfig['globalBW'], 
            radioConfig['subNetworkBW'], 
            radioConfig['routerBW']],
          [ radioConfig['globalMaxDepth'], 
            radioConfig['subNetworkMaxDepth'], 
            radioConfig['routerMaxDepth']])

        #To base station: no queueing
        if moteId == self.bsId:
            self.sendMsg(self.source,
              moteId, 
              setProbeScheduleMsg.get_amType(),
              0,
              setProbeScheduleMsg)
        #To others, must be queue-aware
        else:
            self.send(moteId, setProbeScheduleMsg)

    def configureMaxDownloadRounds(self, moteId, config):
        radioConfig = constants.DEFAULT_RADIO_CONFIG.copy()
        radioConfig.update(config)
        setMaxDownloadRoundsMsg = SetMaxDownloadRounds.SetMaxDownloadRounds(
          radioConfig['maxDownloadRounds']
          )
        print "Setting MDR to ", radioConfig['maxDownloadRounds']
        if moteId == self.bsId:
            self.sendMsg(self.source,
              moteId, 
              setMaxDownloadRoundsMsg.get_amType(),
              0,
              setMaxDownloadRoundsMsg)
        else:
            self.send(moteId, setMaxDownloadRoundsMsg)

        time.sleep(1)


    def addSource(self, s, isPrimary=True):
        '''There should be one primary source (e.g. serial connection
        to a basestation mote). This is where we will send all of the
        control messages. Additional sources can be added as in the
        original MoteIF, but all control messages will go to the
        primary. The send() function will send to the primary source
        unless specifically directed to do otherwise.'''
        if self.source and isPrimary:
            raise MultipleSourceException()
        else:
            s = MoteIF.addSource(self, s)
            if isPrimary:
                self.source = s
            return s

    def downloadStart(self, bsId, networkSegment, source=None):
        if not source:
            source = self.source
        downloadMsg = CxDownload.CxDownload()
        downloadMsg.set_networkSegment(networkSegment)
        t0 = time.time()
        downloadMsg.set_unixTS(t0)

        error = self.sendMsg(source, bsId, 
          downloadMsg.get_amType(), 0, downloadMsg)
        #return the unix time that the download command was sent
        return (time.time() + t0)/2

    def sendWorker(self):
        while not self.finishedListener.finished:
            try:
                (source, addr, msg) = self.txQueue.get(True, 0.1)
                while not self.fwdStatusListener.spaceFree and not self.finishedListener.finished:
                    print "TXQ SW W %u %u %x"%(addr, self.fwdStatusListener.spaceFree, self.finishedListener.finished)
                    with self.fwdStatusListener.cv:
                        #check in on the status and whether or not the
                        # thread is finished
                        self.fwdStatusListener.cv.wait(1.0)
                if not self.finishedListener.finished:
                    print "TXQ SW TX %u %u %x"%(addr, self.fwdStatusListener.spaceFree, self.finishedListener.finished)
                    with self.fwdStatusListener.cv:
                        self.sendMsg(source, addr, msg.get_amType(), 0, msg)
                        self.fwdStatusListener.spaceFree -= 1
                else:
                    print "TXQ SW DROP %u %u %x"%(addr, self.fwdStatusListener.spaceFree, self.finishedListener.finished)
                    pass
            except Queue.Empty:
#                 print "TXQ E"
                #OK, we didn't get a transmit in the last second.
                pass
        while not self.txQueue.empty():
            (source, addr, msg) = self.txQueue.get()
            print "TXQ SW DROP %u %u %x"%(addr, self.fwdStatusListener.spaceFree, self.finishedListener.finished)

    
        
    def send(self, addr, msg, source=None):
        if addr == self.bsId:
            print "Attempting remote send to base station?"
            return TOS.EINVAL
        if not source:
            source = self.source
        self.txQueue.put( (source, addr, msg))
        print "TXQ PUT", (source, addr, msg)
        return TOS.SUCCESS

    def readNext(self):
        return self.eosQueue.get(5.0)

    def clearRXQueue(self):
        time.sleep(1)
        print "Clearing RX Queue"
        while not self.receiveQueue.empty():
            time.sleep(1)
            print "Still waiting for queue to clear"
        print "QUEUE CLEARED"
