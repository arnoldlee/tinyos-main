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

import Tkinter
from Tkinter import *

import tools.cx.constants as constants
import tools.cx.CXController as CXController
from tools.dashboard.DatabaseQuery import DatabaseQuery
import tools.cx.DumpCSV as DumpCSV

from threading import Thread
from tools.serial.tools.list_ports import comports

from tools.cx.messages import SetBaconSampleInterval
from tools.cx.messages import SetToastSampleInterval
from tools.cx.messages import SetProbeSchedule

import time

def getDisplayVal(rootStr, channel):
    return "%s (c. %u)"%(rootStr, channel)
   
class ProgressWindow(Toplevel):
    def __init__(self, onClose):
        Toplevel.__init__(self)
        self.protocol("WM_DELETE_WINDOW", onClose)
        self.title = "Download Progress"
        self.focus_set()

        self.messageFrame = Frame(self)
        self.messageText = Text(self.messageFrame, height=10, width=70,
          background='white')

        self.scroll = Scrollbar(self.messageFrame)
        self.messageText.configure(yscrollcommand=self.scroll.set)
        self.scroll.configure(command = self.messageText.yview)

        self.scroll.pack(side="right", fill="y")
        self.messageText.pack(side="left", fill="both", expand=True)
        self.messageFrame.pack(fill="both", expand=True)


    def addMessage(self, message):
        self.messageText.insert(END, message)
        self.messageText.yview(END)

class ControlFrame(Frame):
    DEFAULT_COM_STRING = "<no device detected>"

    DEFAULT_TYPE_STRING = "All Types"
    ROUTERS_STR = "Routers"
    SUBNETWORK_STR = "Manual Subnetwork"
    GLOBAL_STR = "Global"
    DEFAULT_DOWNLOAD_TARGET = (getDisplayVal(SUBNETWORK_STR, 
      constants.CHANNEL_SUBNETWORK_DEFAULT), 
      constants.NS_SUBNETWORK, 
      constants.CHANNEL_SUBNETWORK_DEFAULT)    
    DEFAULT_SITE_STRING = "All Sites"
    SPACING = 10
    DEFAULT_DATA_DIR = "data"

    DT_ALL_STR = "Recover all"
    DT_RECENT_STR = "New data only"
    DT_STATUS_STR = "Data status update only"

    def __init__(self, parent, hub, dbFile, **args):
        Frame.__init__(self, parent, **args)
        
        self.db = DatabaseQuery(dbFile)
        self.dbFile = dbFile
        self.hub = hub
        self.channels = [0, 31, 63, 95, 159, 191, 223]
        self.connected = False
        self.comDict={}
        self.initUI()
    
    def removeProgressWindow(self):
        self.progressWindow.destroy()
        del self.progressWindow
        self.progressWindow = None

    def progressMessage(self, message):
        if not self.progressWindow:
            self.progressWindow = ProgressWindow(self.removeProgressWindow)
        self.progressWindow.addMessage(message)
        print "PROG %.2f %s"%(time.time(), message,),

    def deviceDetection(self):
        """ Detect serial devices by using the built-in comports command in pyserial.
        """
        # make dictionary with (description, comport)
        newDict = {}
        ports = sorted(comports())
        for port, desc, hwid in ports:
            newDict["%s (%s)"%(port, desc)] = port
        
        # call disconnect function if the current device disappears
        if self.connected and self.comVar.get() not in newDict:
            self.disconnect()
        
        # update menu when not currently connected
        if newDict != self.comDict:
            
            # reset menu
            menu = self.comOption["menu"]
            menu.delete(0, "end")
            
            # keep current selection
            oldIndex = self.comVar.get()
            
            # if devices were found
            if newDict:
                
                # populate menu
                for key in sorted(newDict.keys()):    
                    menu.add_command(label=key, command=Tkinter._setit(self.comVar, key))
                
                # choose first port if no port was previously selected
                if oldIndex not in newDict:
                    self.comVar.set(sorted(newDict.keys())[0])
#                 self.downloadButton.config(state=NORMAL )
                #TODO: update state of commit, discover, download buttons
            else:
                menu.add_command(label=self.DEFAULT_COM_STRING, command=Tkinter._setit(self.comVar, self.DEFAULT_COM_STRING))
                self.comVar.set(self.DEFAULT_COM_STRING)
#                 self.downloadButton.config(state=DISABLED )
                #TODO: disable commit, discover, and download buttons.
            # update
            self.comDict = newDict
        # run detection again after 1000 ms
        self.comOption.after(1000, self.deviceDetection)
    
    def initUI(self):
        self.progressWindow = None

        self.comFrame = Frame(self, padx=self.SPACING)        
        self.comLabel = Label(self.comFrame,
          text="Basestation:")
        self.comLabel.grid(column=0, row=0)
        self.comVar = StringVar()        
        self.comVar.set(self.DEFAULT_COM_STRING)
        self.comOption = OptionMenu(self.comFrame, self.comVar,
          [self.DEFAULT_COM_STRING])
        self.comOption.config(width=25)
        self.comOption.grid(column=1,row=0)
        self.comFrame.grid(column=0, row=0)
        
        self.commitFrame = Frame(self, padx=self.SPACING)
        self.commitButton = Button(self.commitFrame, 
          text="Commit Changes", 
          command=self.commitChanges, state=DISABLED)
        self.commitButton.grid(column=0, row=0)
        self.commitFrame.grid(column=1, row=0)

        self.discoverFrame = Frame(self, padx=self.SPACING)
        self.discoverButton = Button(self.discoverFrame,
          text="Discover Network",
          command=self.discoverNetwork)
        self.discoverButton.grid(column=0, row=0)
        self.discoverFrame.grid(column=2, row=0)

        self.routerDownloadFrame = Frame(self, padx=self.SPACING)
        self.routerDownloadButton = Button(self.routerDownloadFrame,
          text="Router Download",
          command = self.routerDownload)
        self.routerDownloadButton.grid(column=0, row=0)
        self.routerDownloadFrame.grid(column=3, row=0)
        #TODO: would be cool to disable this if no routers have been
        # detected
        
        self.generateCSVFrame = Frame(self, padx=self.SPACING)
        self.generateCSVButton = Button(self.generateCSVFrame,
          text="Generate CSV Files",
          command=self.generateCSV)
        self.generateCSVButton.grid(column=0, row=0)
        self.generateCSVFrame.grid(column=4, row=0)
#         self.selectionFrame = Frame(self, padx=self.SPACING)
#         self.selectionFrame.grid(column=0, row=0)
#         #
#         #
#         #
#         self.allFrame = Frame(self.selectionFrame, padx=self.SPACING)
#         
#         self.allLabel = Label(self.allFrame, text="All: ")
#         self.allLabel.grid(column=0, row=0)
#         
#         self.allTypeVar = StringVar()        
#         self.allTypeVar.set(self.DEFAULT_TYPE_STRING)
#         self.allTypeOption = OptionMenu(self.allFrame, self.allTypeVar, [self.DEFAULT_TYPE_STRING])
#         self.allTypeOption.config(state=DISABLED)
#         self.allTypeOption.config(width=len(self.DEFAULT_TYPE_STRING))
#         self.allTypeOption.grid(column=1, row=0)
#         
#         self.allButton = Button(self.allFrame, text="Select", command=self.selectAll)
#         self.allButton.grid(column=2, row=0)
#         
#         self.allFrame.grid(column=0, row=0)
# 
# 
#         #
#         #
#         #
#         self.siteFrame = Frame(self.selectionFrame, padx=self.SPACING)
#         
#         self.siteLabel = Label(self.siteFrame, text="Site: ")
#         self.siteLabel.grid(column=0, row=0)
#         
#         self.siteSiteVar = StringVar()        
#         self.siteSiteVar.set(self.DEFAULT_SITE_STRING)
#         self.siteSiteOption = OptionMenu(self.siteFrame, self.siteSiteVar, [self.DEFAULT_SITE_STRING])
#         self.siteSiteOption.config(state=DISABLED)
#         self.siteSiteOption.config(width=len(self.DEFAULT_SITE_STRING))
#         self.siteSiteOption.grid(column=1, row=0)
# 
#         self.siteTypeVar = StringVar()        
#         self.siteTypeVar.set(self.DEFAULT_TYPE_STRING)
#         self.siteTypeOption = OptionMenu(self.siteFrame, self.siteTypeVar, [self.DEFAULT_TYPE_STRING])
#         self.siteTypeOption.config(state=DISABLED)
#         self.siteTypeOption.config(width=len(self.DEFAULT_TYPE_STRING))
#         self.siteTypeOption.grid(column=2, row=0)
# 
#         self.siteButton = Button(self.siteFrame, text="Select", command=self.selectSite)
#         self.siteButton.grid(column=3, row=0)
# 
#         self.siteFrame.grid(column=0, row=1)
        
        #
        #
        #
#         self.commitFrame = Frame(self, padx=self.SPACING)
#         self.commitFrame.grid(column=1, row=0)
        
        #
#         self.downloadFrame = Frame(self, padx=self.SPACING)
#         self.downloadLabel = Label(self.downloadFrame,
#           text="Download From:")
#         self.downloadLabel.grid(column=0, row=0)
# 
#         self.downloadVar = StringVar()
#         self.downloadOption = OptionMenu(self.downloadFrame,
#           self.downloadVar, [])
#         self.updateDownloadOptions({})
#         self.selectDownloadTarget(self.DEFAULT_DOWNLOAD_TARGET)
#         self.downloadOption.grid(column=1, row=0)

#         self.downloadButton = Button(self.downloadFrame, text="Download", command=self.download)
#         self.downloadButton.grid(column=1, row=1)
        
#         self.repairVar = IntVar()
#         self.repairButton = Checkbutton(self.downloadFrame,
#           text="Repair", variable=self.repairVar)
#         self.repairButton.select()
#         self.repairButton.grid(column=2, row=1)

#         self.downloadTypeVar = StringVar()
#         self.downloadTypeVar.set(self.DT_ALL_STR)
#         self.downloadTypeOption = OptionMenu(self.downloadFrame,
#           self.downloadTypeVar, 
#           self.DT_ALL_STR, self.DT_RECENT_STR, self.DT_STATUS_STR)
#         self.downloadTypeOption.grid(column=2, row=1)


        #
        # Status interval widgets
        #
        rangeFrame = Frame(self, padx=self.SPACING)
        
        self.rangeLabel = Label(rangeFrame, text="Status Interval: ")
        self.fromPrefixLabel = Label(rangeFrame, text="From")
        self.earliestSpinbox = Spinbox(rangeFrame, from_=1, to=36500, increment=1.0, width=5, justify=RIGHT, command=self.earliestSpinboxConsistency)
        self.fromSuffixLabel = Label(rangeFrame, text="days ago. ")

        self.toPrefixLabel = Label(rangeFrame, text="To")
        self.latestSpinbox = Spinbox(rangeFrame, from_=0, to=36500, increment=1.0, width=5, justify=RIGHT, command=self.latestSpinboxConsistency)
        self.toSuffixLabel = Label(rangeFrame, text="days ago.")

        self.earliestSpinbox.bind('<Return>', self.earliestSpinboxConsistency)
        self.latestSpinbox.bind('<Return>', self.latestSpinboxConsistency)
        
        # set default interval to 7 days
        self.earliestSpinbox.delete(0, END)
        self.earliestSpinbox.insert(0, "7")
        
        self.rangeLabel.grid(column=0, row=0)
        self.fromPrefixLabel.grid(column=1, row=0)
        self.earliestSpinbox.grid(column=2, row=0)
        self.fromSuffixLabel.grid(column=3, row=0)
        self.toPrefixLabel.grid(column=4, row=0)
        self.latestSpinbox.grid(column=5, row=0)
        self.toSuffixLabel.grid(column=6, row=0)
        rangeFrame.grid(column=0, row=1)
        
        #
        # detect attached nodes
        #
        self.deviceDetection()

    def earliestSpinboxConsistency(self, event=None):
        earliest = int(self.earliestSpinbox.get())
        latest = int(self.latestSpinbox.get())
        
        if  earliest <= latest:
            self.latestSpinbox.delete(0, END)
            self.latestSpinbox.insert(0, str(earliest - 1) )
            
        self.hub.node.redrawAllNodes()

    def latestSpinboxConsistency(self, event=None):
        earliest = int(self.earliestSpinbox.get())
        latest = int(self.latestSpinbox.get())
        
        if  earliest <= latest:
            self.earliestSpinbox.delete(0, END)
            self.earliestSpinbox.insert(0, str(latest + 1) )
            
        self.hub.node.redrawAllNodes()
   
    def addDownloadOption(self, menu, rootStr, networkSegment, channel):
        displayVal = getDisplayVal(rootStr, channel)
        menu.add_command(label=displayVal,
          command = lambda target=(displayVal, networkSegment, channel):
            self.selectDownloadTarget(target))
        
    def updateDownloadOptions(self, siteChannels):
        menu = self.downloadOption["menu"]
        menu.delete(0, "end")
        self.addDownloadOption(menu, self.ROUTERS_STR, 
          constants.NS_ROUTER, 
          constants.CHANNEL_ROUTER)
        self.addDownloadOption(menu, self.GLOBAL_STR,
          constants.NS_GLOBAL, 
          constants.CHANNEL_GLOBAL)
        for channel in sorted(siteChannels):
            self.addDownloadOption(menu, 
              siteChannels[channel], 
              constants.NS_SUBNETWORK,
              channel)
        for channel in self.channels:
            self.addDownloadOption(menu, self.SUBNETWORK_STR,
              constants.NS_SUBNETWORK, 
              channel)

    def updateSites(self, sites):
        """ Populates drop-down menu with available sites.
            Called from redrawAllNodes in NodeFrame.
        """
        #
        # populate "Site" menu
        #
        menu = self.siteSiteOption["menu"]
        menu.delete(0, "end")
        
        menu.add_command(label=self.DEFAULT_SITE_STRING, command=lambda site=self.DEFAULT_SITE_STRING: self.selectSiteSite(site))
        
        for site in sorted(sites.keys()):
            if site != 0:
                menu.add_command(label=site, command=lambda site=site: self.selectSiteSite(site))
                if self.siteSiteVar.get() == self.DEFAULT_SITE_STRING:
                    self.siteSiteOption.config(state=NORMAL)
    

    def updateTypes(self, types):
        """ Populates drop-down menu with available sensor types.
            Called from redrawAllNodes in NodeFrame.
        """
        return       
        #
        # populate "All" menu
        #
        menu = self.allTypeOption["menu"]
        menu.delete(0, "end")
        
        menu.add_command(label=self.DEFAULT_TYPE_STRING, command=lambda key=self.DEFAULT_TYPE_STRING: self.selectAllType(key))
        
        for key in sorted(types.keys()):
            if key != 0:
                #menu.add_command(label=key, command=Tkinter._setit(self.allTypeVar, key))
                menu.add_command(label=key, command=lambda key=key: self.selectAllType(key))
                if self.allTypeVar.get() == self.DEFAULT_TYPE_STRING:
                    #self.allTypeVar.set(key)
                    self.allTypeOption.config(state=NORMAL)

        #
        # populate "Site" menu
        #
        menu = self.siteTypeOption["menu"]
        menu.delete(0, "end")
        
        menu.add_command(label=self.DEFAULT_TYPE_STRING, command=lambda key=self.DEFAULT_TYPE_STRING: self.selectSiteType(key))
        
        for key in sorted(types.keys()):
            if key != 0:
                menu.add_command(label=key, command=lambda key=key: self.selectSiteType(key))
                if self.siteTypeVar.get() == self.DEFAULT_TYPE_STRING:
                    self.siteTypeOption.config(state=NORMAL)


    def selectAllType(self, type):
        """ Select all nodes with the specified sensor type attached.
        """        
        self.allTypeVar.set(type)


    def selectAll(self):
        self.hub.display.updateSite("All Sites")
        self.hub.display.updateType(self.allTypeVar.get())
        self.hub.display.redrawAll()
        self.hub.node.redrawAllNodes()


    def selectSiteSite(self, site):
        """ Select all nodes within the specified site.
        """        
        self.siteSiteVar.set(site)

    def selectSiteType(self, type):
        """ Select nodes with the specified sensor type attached in specific site.
        """        
        self.siteTypeVar.set(type)

    def selectSite(self):
        self.hub.display.updateSite(self.siteSiteVar.get())
        self.hub.display.updateType(self.siteTypeVar.get())
        self.hub.display.redrawAll()        
        self.hub.node.redrawAllNodes()

    def selectDownloadTarget(self, t):
        (displayVal, networkSegment, target) = t
        print "SDT:", t
        self.downloadVar.set(displayVal)
        self.networkSegment = networkSegment
        self.downloadChannel = target

    def patchDownloadRunner(self):
        configMap= {'subNetworkChannel':self.patchChannel, 
          'maxDownloadRounds':1000}
        cxCtrl = CXController.CXController(self.dbFile)
        cxCtrl.download('serial@%s:115200'%(self.comDict[self.comVar.get()]),
          constants.NS_SUBNETWORK, configMap, 
          refCallBack=self.refCallBack,
          eosCallBack=self.eosCallBack,
          repairCallBack=self.repairCallBack,
          finishedCallBack=self.downloadFinished,
          requestMissing=True)
    
    def routerDownloadRunner(self):
        configMap= {'maxDownloadRounds':1000}
        cxCtrl = CXController.CXController(self.dbFile)
        cxCtrl.download('serial@%s:115200'%(self.comDict[self.comVar.get()]),
          constants.NS_ROUTER, configMap, 
          refCallBack=self.refCallBack,
          eosCallBack=self.eosCallBack,
          repairCallBack=self.repairCallBack,
          finishedCallBack=self.downloadFinished,
          requestMissing=True)

    def discoverRunner(self):
        configMap= {'maxDownloadRounds':1}
        cxCtrl = CXController.CXController(self.dbFile)
        cxCtrl.download('serial@%s:115200'%(self.comDict[self.comVar.get()]),
          constants.NS_GLOBAL, configMap, 
          refCallBack=self.refCallBack,
          eosCallBack=self.eosCallBack,
          repairCallBack=self.repairCallBack,
          finishedCallBack=self.downloadFinished,
          requestMissing=False)

    def discoverNetwork(self):
        self.progressMessage("Network Discovery Started\n")
        self.discoverButton.config(text="DISCOVERING", bg="green",
          state=DISABLED)
        self.commitButton.config(text="BUSY", bg="yellow",
          state=DISABLED)
        self.routerDownloadButton.config(bg="yellow", text="BUSY",
          state=DISABLED)
        self.downloadThread = Thread(target=self.discoverRunner,
          name="discoverThread")
        self.downloadThread.daemon = True
        self.downloadThread.start()
        self.downloadProgress()

    def routerDownload(self):
        self.progressMessage( "Router Download Started\n")
        self.routerDownloadButton.config(text="DOWNLOADING", bg="green",
          state=DISABLED)
        self.commitButton.config(text="BUSY", bg="yellow",
          state=DISABLED)
        self.discoverButton.config(text="BUSY", bg="yellow",
          state=DISABLED)
        self.downloadThread = Thread(target=self.routerDownloadRunner,
          name="downloadThread")
        self.downloadThread.daemon = True
        self.downloadThread.start()
        self.downloadProgress()

    def patchDownload(self, channel):
        self.progressMessage( "Patch Download Started\n")
        self.routerDownloadButton.config(text="BUSY", bg="yellow",
          state=DISABLED)
        self.commitButton.config(text="BUSY", bg="yellow",
          state=DISABLED)
        self.discoverButton.config(text="BUSY", bg="yellow",
          state=DISABLED)
        self.patchChannel = channel
        self.downloadThread = Thread(target=self.patchDownloadRunner,
          name="downloadThread")
        self.hub.node.markChannelButtonsBusy(channel)

        self.downloadThread.daemon = True
        self.downloadThread.start()
        self.downloadProgress()
        print "patch download %d"%(channel,)

    def downloadProgress(self):
        """ This function is here to ensure Windows compatibility.
            TKInter on Windows stalls when widgets are updated from other threads.
            This function calls itself every second and checks whether the download
            thread has completed and updates the GUI once done. For some reason the
            thread.join() also stalls the GUI.
        """
        if self.downloadThread.isAlive():
            self.discoverButton.after(1000, self.downloadProgress)
        else:
            self.discoverButton.config(text="Discover Network", bg="gray",
              state=NORMAL)
            self.routerDownloadButton.config(text="Router Download",
              bg="gray", state=NORMAL)
            self.hub.node.loadSettings()
            self.hub.node.redrawAllNodes()

    def downloadFinished(self, masterId, message):
        """ Callback function. Called by the download thread once done and 
            updates the progress windows with status updates and spawns the
            CSV thread to generate data files from the database.
        """
        self.progressMessage(message)
        (masterId, contacted, found) = self.db.getLastDownloadResults(masterId)
        self.progressMessage("Download finished: %u/%u identified nodes contacted\n"%(contacted, found))
#        self.csvRunner()
#         self.csvThread = Thread(target=self.csvRunner,
#           name="csvThread")
#         self.csvThread.daemon = True
#         self.csvThread.start()
    
    def generateCSV(self):
        self.csvThread = Thread(target=self.csvRunner,
          name="csvThread")
        self.csvThread.daemon = True
        self.csvThread.start()

        

    def csvRunner(self):
        self.progressMessage("Processing data to CSV files. This may take many minutes.\n")
        DumpCSV.dumpCSV(self.dbFile, self.DEFAULT_DATA_DIR,
          self.progressMessage)
        self.progressMessage("CSV files ready (under '%s' directory)\n"%
          self.DEFAULT_DATA_DIR )
        for (nodeId, barcodeId, lastSampleTime, lastContact, batteryVoltage) in self.db.contactSummary():
            self.progressMessage("Node %s last sample %s s ago last contact %u s ago battery %s v\n"%(
              barcodeId if barcodeId else hex(nodeId), 
              "%.2f"%(time.time() - lastSampleTime) if lastSampleTime else "NA", 
              time.time() - lastContact,
              "%.2f"%batteryVoltage if batteryVoltage else "NA"))

    def refCallBack(self, node, neighbors, pushCookie, writeCookie,
          missingLength):
        self.progressMessage("Contacted %x (%u neighbors). %d queued, %d in current request\n"%(node, len(neighbors), writeCookie-pushCookie, missingLength))

    def eosCallBack(self, node, status):
        if status == 0:
            self.progressMessage("Node %x NOT reached\n"%(node,))
        if status == 1:
            self.progressMessage(" Node %x transfer completed\n"%(node,))
        if status == 2:
            self.progressMessage(" Node %x transfer continues\n"%(node,))

    def repairCallBack(self, node, length, totalMissing):
        self.progressMessage("Node %x request %u (missing: %u)\n"%(node, length, totalMissing))

    def outboundCallback(self, node):
        self.progressMessage("Sent settings-change to %x.\n"%(node))

    def commitChanges(self):
        self.progressMessage("Committing settings changes, please wait.\n")
        self.discoverButton.config(bg="yellow", text="BUSY",
          state=DISABLED)
        self.routerDownloadButton.config(bg="yellow", text="BUSY",
          state=DISABLED)
        self.commitButton.config(bg="green", text="COMMITTING",
          state=DISABLED)
        self.downloadThread = Thread(target=self.commitChangesRunner,
          name="commitThread")
        self.downloadThread.daemon = True
        self.downloadThread.start()
        self.downloadProgress()
        

    def commitChangesRunner(self):
        changeMessages = {}
        for barcode in self.hub.node.settings:
            (nodeId, oInterval, oChannel, oRole) = self.hub.node.originalSettings[barcode]
            (nodeId, mInterval, mChannel, mRole) = self.hub.node.settings[barcode]
            print "Check modifications for %s (%u)"%(barcode, nodeId)
            if oInterval != mInterval:
                print "%s Interval %u -> %u"%(barcode, oInterval, mInterval)
                setBaconInterval = SetBaconSampleInterval.SetBaconSampleInterval(mInterval)
                changeMessages[nodeId] = changeMessages.get(nodeId, [])+[setBaconInterval]
                setToastInterval = SetToastSampleInterval.SetToastSampleInterval(mInterval)
                changeMessages[nodeId] = changeMessages.get(nodeId, [])+[setToastInterval]
            if oChannel != mChannel:
                if mRole == constants.ROLE_ROUTER:
                    print "Router %s Channel %u -> %u"%(barcode, oChannel, mChannel)
                    setProbeSchedule = SetProbeSchedule.SetProbeSchedule(constants.DEFAULT_PROBE_INTERVAL,
                      [constants.CHANNEL_GLOBAL, mChannel, constants.CHANNEL_ROUTER],
                      [1, 1, 1], # legacy: probe rate divider
                      [2, 2, 2], # boundary width
                      [2*constants.SEGMENT_MAX_DEPTH, constants.SEGMENT_MAX_DEPTH, constants.SEGMENT_MAX_DEPTH])
                elif mRole == constants.ROLE_LEAF:
                    print "Leaf %s Channel %u -> %u"%(barcode, oChannel, mChannel)
                    setProbeSchedule = SetProbeSchedule.SetProbeSchedule(constants.DEFAULT_PROBE_INTERVAL,
                      [constants.CHANNEL_GLOBAL, mChannel, constants.CHANNEL_ROUTER],
                      [1, 1, 1], # legacy: probe rate divider
                      [2, 2, 2], # boundary width
                      [2*constants.SEGMENT_MAX_DEPTH, constants.SEGMENT_MAX_DEPTH, 0])
#                     setProbeSchedule = SetProbeSchedule(constants.PROBE_INTERVAL,
#                       [constants.GLOBAL_CHANNEL, mChannel, constants.ROUTER_CHANNEL],
#                       [1, 1, 1], # legacy: probe rate divider
#                       [2, 2, 2], # boundary width
#                       [2*constants.MAX_DEPTH, constants.MAX_DEPTH, 0])
                changeMessages[nodeId] = changeMessages.get(nodeId, [])+[setProbeSchedule]
        if changeMessages:
            cxCtrl = CXController.CXController(self.dbFile)
    
            configMap= { 'maxDownloadRounds':1000}
            cxCtrl.download('serial@%s:115200'%(self.comDict[self.comVar.get()]),
              constants.NS_GLOBAL, configMap, 
              refCallBack=self.refCallBack,
              eosCallBack=self.eosCallBack,
              repairCallBack=self.repairCallBack,
              finishedCallBack=self.downloadFinished,
              requestMissing=False,
              outboundMessages = changeMessages,
              outboundCallback = self.outboundCallback)
            self.progressMessage("""Changes sent to network.\n""")
        else:
            self.progressMessage("No changes to apply.\n")


    def refresh(self):
        self.hub.node.initUI()
    
    def settingsChanged(self, changesPresent):
        if changesPresent:
            self.commitButton.config(text="Commit Changes", 
              state=NORMAL, bg="gray")
        else:
            self.commitButton.config(text="Commit Changes", 
              state=DISABLED, bg="gray")

    
    
