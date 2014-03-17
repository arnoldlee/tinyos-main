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

import sys
import time
import ast

from tools.labeler.TOS import TOS
from tools.cx.listeners import RecordListener
from tools.cx.listeners import PrintfListener
from tools.cx.messages import PrintfMsg
from tools.cx.messages import LogRecordDataMsg

from tools.cx.listeners import PongListener
from tools.cx.messages import PongMsg
from tools.cx.messages import PingMsg
from tools.cx.messages import CxRecordRequestMsg

from tools.cx.db import Database

from tools.cx.decoders import BaconSample
from tools.cx.decoders import ToastSample
from tools.cx.decoders import BaconSettings
from tools.cx.decoders import ToastConnection
from tools.cx.decoders import ToastDisconnection
from tools.cx.decoders import Phoenix
from tools.cx.decoders import LogPrintf
from tools.cx.decoders import NetworkMembership
from tools.cx.decoders import Tunneled

from tools.cx.messages import CxStatus
from tools.cx.CXMoteIF import CXMoteIF

from tools.cx.listeners import StatusTimeRefListener

from tools.cx import constants

from tools.cx.messages import SetBaconSampleInterval
from tools.cx.messages import SetToastSampleInterval


class Dispatcher(object):
    def __init__(self, motestring, db, configMap={},
      configFile=None):
        #hook up to mote
        self.mif = CXMoteIF()
        self.tos_source = self.mif.addSource(motestring)
        if self.mif.identifyMote():
            #format printf's correctly
            self.mif.addListener(PrintfListener.PrintfListener(self.mif.bsId), 
              PrintfMsg.PrintfMsg)
            self.mif.addListener(RecordListener.RecordListener(db), 
              LogRecordDataMsg.LogRecordDataMsg)
            self.mif.addListener(PongListener.PongListener(), 
              PongMsg.PongMsg)
            if configFile:
                #evaluate each key:=value pair and stick it into config
                with open(configFile, 'r') as f:
                    for line in f:
                        if not line.startswith('#'):
                            r = line.split(':=')
                            configMap[r[0]] = ast.literal_eval(r[1])
            self.mif.configureMoteRadio(self.mif.bsId, configMap)
            time.sleep(1)
            self.mif.configureMaxDownloadRounds(self.mif.bsId, configMap)
        else:
            raise Exception("Connected mote did not respond to ID request (has it been set up as a BaseStation?")


    def stop(self):
        print "clearing"
        self.mif.clearRXQueue()
        print "cleared"
        self.mif.finishAll()
        print "finished"

    def send(self, m, dest=0):
        return self.mif.send(dest, m)


class CXController(object):
    def __init__(self, dbName):
        self.dbName = dbName
        
    #TODO: add per-node cookie range parameter for selective recovery.
    def download(self, packetSource, networkSegment=constants.NS_GLOBAL,
            configMap={}, configFile=None, refCallBack=None,
            eosCallBack=None, repairCallBack=None,
            finishedCallBack=None, requestMissing=True,
            outboundMessages={}, outboundCallback=None):
        print packetSource
        db = Database.Database(self.dbName)
        try:
            d = Dispatcher(packetSource, db, configMap=configMap, configFile=configFile)
            bsId = d.mif.bsId
        except:
            if finishedCallBack:
                finishedCallBack(constants.BCAST_ADDR, """Could not connect to base station.
      Make sure you've selected the right device and make sure
      it has been set up as a base station.
    """) 
                raise
            else:
                raise

        db.addDecoder(BaconSample.BaconSample)
        db.addDecoder(ToastSample.ToastSample)
        db.addDecoder(ToastConnection.ToastConnection)
        db.addDecoder(ToastDisconnection.ToastDisconnection)
        db.addDecoder(Phoenix.Phoenix)
        db.addDecoder(BaconSettings.BaconSettings)
        db.addDecoder(LogPrintf.LogPrintf)
        db.addDecoder(NetworkMembership.NetworkMembership)
        #man that is ugghly to hook 
        t = db.addDecoder(Tunneled.Tunneled)
        t.receiveQueue = d.mif.receiveQueue
        pingId = 0

        refListener = StatusTimeRefListener.StatusTimeRefListener(db, refCallBack)
        d.mif.addListener(refListener, CxStatus.CxStatus)
        
        try:
            print "Wakeup start", time.time()

            refListener.downloadStart = d.mif.downloadStart(bsId, 
              networkSegment)
            error = TOS.SUCCESS
            firstContact = True
            nodes=set()
            retryMap = {}
            while not d.mif.finishedListener.finished:
                eos = d.mif.readNext()
                if eos:
                    node = eos.get_owner()
                    if node != bsId:
                        nodes.add(node)
                    if eosCallBack:
                        eosCallBack(node, eos.get_status())
                    if node in outboundMessages and outboundMessages[node]:
                        messageList = outboundMessages[node]
                        message = messageList[0]
                        messageList = messageList[1:]
                        d.send(message, node)
                        if outboundCallback:
                            outboundCallback(node)
                        outboundMessages[node] = messageList

                    if eos.get_status() == 1 and requestMissing:
                        if node == bsId:
                            if firstContact:
                                firstContact = False
                            else:
                                pass
    #                             (missingMap, allMissing) = db.findMissing(incrementRetries=False)
    #                             outstandingNodes = nodes & set(missingMap.keys())
    #                             if outstandingNodes:
    #                                 print "Gaps remain, keep-alive", outstandingNodes
    #                                d.mif.keepAlive(bsId)
                            print "Skip BS pseudo cookie"
                        else:
                            #TODO: if we are doing selective recovery,
                            # then this should call a function that
                            # takes in a cookie range and only return gaps
                            # falling in that range.
                            missingT = db.allNodeMissing(node)
                            totalMissing=-1
    #                         totalMissing = db.totalMissing(eos.get_owner()
                            if missingT:
                                (gapList, totalMissing) = missingT
                                if node not in retryMap:
                                    retryMap[node] = {}
                                nodeRetryMap = retryMap[node]
                                for (node_id, cookie, nextCookie, missing, retry) in gapList:
                                    print "REC %u check gap %u"%(node_id, nextCookie)
                                    if nextCookie not in nodeRetryMap or nodeRetryMap[nextCookie] < constants.MAX_RECOVERY_ATTEMPTS:
                                        msg = CxRecordRequestMsg.CxRecordRequestMsg()
                                        msg.set_node_id(node_id)
                                        msg.set_cookie(nextCookie)
                                        msg.set_length(min(missing, constants.MAX_REQUEST_UNIT))
                                        if repairCallBack:
                                            repairCallBack(msg.get_node_id(),
                                              msg.get_length(), totalMissing)
                                        d.send(msg, msg.get_node_id())
                                        nodeRetryMap[nextCookie] = nodeRetryMap.get(nextCookie,0) + 1
                                        print "REC %u requesting %u at %u from %u (attempt %u)"%(node, msg.get_length(),
                                          msg.get_cookie(),
                                          msg.get_node_id(),
                                          nodeRetryMap[nextCookie])
                                        break
                                    elif nextCookie in nodeRetryMap and nodeRetryMap[nextCookie] >= constants.MAX_RECOVERY_ATTEMPTS:
                                        #determine if this gap is big enough so that we should download part of it
                                        subpart = constants.MAX_RECOVERY_ATTEMPTS / 5
                                        sublen = min(missing, constants.MAX_REQUEST_UNIT) - subpart*1024
                                        if(sublen >= 1024):
                                            msg = CxRecordRequestMsg.CxRecordRequestMsg()
                                            msg.set_node_id(node_id)
                                            msg.set_cookie(nextCookie + subpart*1024)
                                            msg.set_length(min(missing - subpart*1024, constants.MAX_REQUEST_UNIT))
                                            if repairCallBack:
                                                repairCallBack(msg.get_node_id(),
                                                  msg.get_length(), totalMissing-subpart*1024)
                                            d.send(msg, msg.get_node_id())
                                            nodeRetryMap[nextCookie] = nodeRetryMap.get(nextCookie,0) + 1
                                            print "REC %u requesting %u at %u from %u (attempt %u)"%(node, msg.get_length(),
                                              msg.get_cookie(),
                                              msg.get_node_id(),
                                              nodeRetryMap[nextCookie])
                                            break
                                        else:
                                            continue
                                    else:
                                        print "REC %u give up on gap %u"%(node, nextCookie)
                            else:
                                print "REC %u no gap"%node

        #these two exceptions should just make us clean up/quit
        except KeyboardInterrupt:
            pass
        except EOFError:
            pass
        finally:
            print "Cleaning up"
            d.stop()
            db.stop()
        print "done for real"
        if finishedCallBack:
            finishedCallBack(d.mif.bsId, "Finished.\n")

    def pushConfig(self, packetSource, networkSegment, configFile,
          newConfigFile, nodeList):
        db = Database.Database(self.dbName)
        d = Dispatcher(packetSource, db, configFile=configFile)
        bsId = d.mif.bsId
        #we will get status refs in this process
        refListener = StatusTimeRefListener.StatusTimeRefListener(db.dbName)
        d.mif.addListener(refListener, StatusTimeRef.StatusTimeRef)

        #Should not be receiving other types of data here.
        db.addDecoder(NetworkMembership.NetworkMembership)
        try:
            refListener.downloadStart = d.mif.downloadStart(bsId,
              networkSegment)

            if error:
                print "Download failed: %x"%error
                pass
            else: 
                for node in nodeList:
                    d.mif.configureMoteRadio(node, newConfigFile)
                d.mif.downloadWait()

        except KeyboardInterrupt:
            pass
        except EOFError:
            pass
        finally:
            print "Cleaning up"
            d.stop()

    def ping(self, packetSource, networkSegment, configFile):
        db = Database.Database(self.dbName)
        d = Dispatcher(packetSource, db, configFile=configFile)
        bsId = d.mif.bsId
        #we will get status refs in this process
        refListener = StatusTimeRefListener.StatusTimeRefListener(db.dbName)
        d.mif.addListener(refListener, StatusTimeRef.StatusTimeRef)

        #Should not be receiving other types of data here.
        db.addDecoder(NetworkMembership.NetworkMembership)
        try:
            refListener.downloadStart = d.mif.downloadStart(bsId,
              networkSegment)

            if error:
                print "Ping failed: %x"%error
                pass
            else: 
                d.mif.downloadWait()

        except KeyboardInterrupt:
            pass
        except EOFError:
            pass
        finally:
            print "Cleaning up"
            d.stop()

    def sleep(self, packetSource, networkSegment, configFile, sleepDuration):
        print "Sleeping for %f" % sleepDuration
        db = Database.Database(self.dbName)
        d = Dispatcher(packetSource, db, configFile=configFile)
        bsId = d.mif.bsId
        try:
            time.sleep(sleepDuration)
        finally:
            print "Cleaning up"
            d.stop()
            db.stop()

    def triggerRouterDownload(self, packetSource, networkSegment, configFile):
        db = Database.Database(self.dbName)
        d = Dispatcher(packetSource, db, configFile=configFile)
        bsId = d.mif.bsId
        #we will get status refs in this process
        refListener = StatusTimeRefListener.StatusTimeRefListener(db.dbName)
        d.mif.addListener(refListener, StatusTimeRef.StatusTimeRef)

        db.addDecoder(BaconSample.BaconSample)
        db.addDecoder(ToastSample.ToastSample)
        db.addDecoder(ToastConnection.ToastConnection)
        db.addDecoder(ToastDisconnection.ToastDisconnection)
        db.addDecoder(Phoenix.Phoenix)
        db.addDecoder(BaconSettings.BaconSettings)
        db.addDecoder(LogPrintf.LogPrintf)
        db.addDecoder(NetworkMembership.NetworkMembership)
        #man that is ugghly to hook 
        t = db.addDecoder(Tunneled.Tunneled)
        t.receiveQueue = d.mif.receiveQueue

        #Should not be receiving other types of data here.
        db.addDecoder(NetworkMembership.NetworkMembership)
        try:
            refListener.downloadStart = d.mif.downloadStart(bsId,
              networkSegment)


            if error:
                print "BS download failed: %x"%error
                pass
            else: 
                downloadMsg = CxDownload.CxDownload()
                downloadMsg.set_networkSegment(constants.NS_SUBNETWORK)
                time.sleep(1)
                error = d.send(downloadMsg, 0xFFFF)
                print "Router download command: ",error
                if error:
                    print "Router download failed"
                else:
                    d.mif.downloadWait()

        except KeyboardInterrupt:
            pass
        except EOFError:
            pass
        finally:
            print "Cleaning up"
            d.stop()

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print "Usage:", sys.argv[0], "packetSource(e.g serial@/dev/ttyUSB0:115200) [networkSegment] [configFile] [-p newConfigFile [node]*] [--ping]" 
        print "  [networkSegment=0] : 0=global 1=subnetwork 2=router"
        print "  -p: push configFile settings to nodes listed"
        sys.exit()

    cxCtrl = CXController("database.sqlite")

    packetSource = sys.argv[1]
    networkSegment = constants.NS_GLOBAL
    configFile = None
    
#     if len(sys.argv) > 2:
#         networkSegment = int(sys.argv[2])
#     if len(sys.argv) > 3:
#         configFile = sys.argv[3]
    if '--segment' in sys.argv:
        networkSegment = int(sys.argv[sys.argv.index('--segment')+1])
    if '--configFile' in sys.argv:
        configFile = sys.argv[sys.argv.index('--configFile')+1]

    if '-p' in sys.argv:
        pIndex= sys.argv.index('-p')
        nodeList = [int(s, 16) for s in sys.argv[pIndex+2:] if s.startswith('0x')]
        nodeList += [int(s) for s in sys.argv[pIndex+2:] if not s.startswith('0x')]
        newConfigFile = sys.argv[pIndex+1]
        print "Pushing config %s to %s"%(newConfigFile, nodeList)
        cxCtrl.pushConfig(packetSource, networkSegment, configFile, newConfigFile, nodeList)
    elif '--ping' in sys.argv:
        cxCtrl.ping(packetSource, networkSegment, configFile)
    elif '--routerDownload' in sys.argv:
        triggerRouterDownload(packetSource, networkSegment, configFile)
    elif '--download' in sys.argv:
        cxCtrl.download(packetSource, networkSegment, configFile=configFile)

    if '--sleep' in sys.argv:
        sleepDuration = float(sys.argv[sys.argv.index('--sleep')+1])
        cxCtrl.sleep(packetSource, networkSegment, configFile, sleepDuration)

