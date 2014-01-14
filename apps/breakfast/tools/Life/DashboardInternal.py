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


from Tkinter import *
import tkMessageBox

#from toaster.MenuFrame import MenuFrame
#from toaster.BaconFrame import BaconFrame
#from toaster.ToastFrame import ToastFrame
#from toaster.GraphFrame import GraphFrame
#from toaster.AdcFrame import AdcFrame
#from dashboard.Handler import Handler
#from dashboard.ScrolledList import ScrolledList

from tools.SimPy.SimPlot import SimPlot 
from tools.dashboard.ScrollNodeFrame import ScrollNodeFrame
from tools.dashboard.ControlFrame import ControlFrame
from tools.dashboard.StatusFrame import StatusFrame
from tools.dashboard.ScrollDisplayFrame import ScrollDisplayFrame
from tools.dashboard.Hub import Hub

from tools.cx.db.DatabaseInit import DatabaseInit

def selectall(event):
    event.widget.select_range(0, END)

def quit(key=None):
    root.quit()

def xscrollSet(lo, hi):
    if float(lo) <= 0.0 and float(hi) >= 1.0:
        # grid_remove is currently missing from Tkinter!
        xscrollbar.tk.call("grid", "remove", xscrollbar)
        xscrollOn = False
    else:
        xscrollbar.grid()
        xscrollOn = True
    xscrollbar.set(lo, hi)        
    
def yscrollSet(lo, hi):
    if float(lo) <= 0.0 and float(hi) >= 1.0:
        # grid_remove is currently missing from Tkinter!
        yscrollbar.tk.call("grid", "remove", yscrollbar)
        yscrollOn = False
    else:
        yscrollbar.grid()
        yscrollOn = True
    yscrollbar.set(lo, hi)        

def updateCanvas(event):        
    canvas.configure(scrollregion=canvas.bbox("all"))

def controlKeyPressed(key=None):
    hub.controlKey = True

def controlKeyReleased(key=None):
    hub.controlKey = False

def shiftKeyPressed(key=None):
    hub.shiftKey = True

def shiftKeyReleased(key=None):
    hub.shiftKey = False

if __name__ == '__main__':
#     dbFile = 'database0.sqlite'
    dbi = DatabaseInit('database')
    dbFile = dbi.dbName
    
    #
    #
    #
    simplot = SimPlot()
    root = simplot.root
    
    hub = Hub()    
    
    controlHeight=60
    centerHeight=500
    statusHeight=80
    WIDTH = 1080
    HEIGHT = controlHeight+centerHeight+20
    MAIN = WIDTH * 2/3
    
    root.geometry(str(WIDTH) + "x" + str(HEIGHT))
    root.title("Dashboard")
    root.bind_class("Entry","<Control-a>", selectall)
    root.bind("<Alt-F4>", quit)
    root.bind('<Control-c>', quit)
    root.protocol("WM_DELETE_WINDOW", quit)
    root.bind('<Control-Button-1>', controlKeyPressed)
    root.bind('<Control-ButtonRelease-1>', controlKeyReleased)
    root.bind('<Shift-Button-1>', shiftKeyPressed)
    root.bind('<Shift-ButtonRelease-1>', shiftKeyReleased)
    
    
    #
    # scroll bars
    #
    xscrollOn = False
    yscrollOn = False
    
    xscrollbar = Scrollbar(root, orient=HORIZONTAL)
    xscrollbar.grid(column=0, row=1, sticky=E+W)
    yscrollbar = Scrollbar(root)
    yscrollbar.grid(column=1, row=0, sticky=N+S)
    
    canvas = Canvas(root, yscrollcommand=yscrollSet, xscrollcommand=xscrollSet)
    canvas.grid(row=0, column=0, sticky=N+S+E+W)
    
    yscrollbar.config(command=canvas.yview)
    xscrollbar.config(command=canvas.xview)
    
    # make the canvas expandable
    root.grid_rowconfigure(0, weight=1)
    root.grid_columnconfigure(0, weight=1)
    
    rootFrame = Frame(canvas)
    rootFrame.rowconfigure(1, weight=1)
    rootFrame.columnconfigure(1, weight=1)
    canvas.create_window(0, 0, anchor=NW, window=rootFrame)
    
    rootFrame.bind("<Configure>", updateCanvas)
    
    #
    # Frames on top of canvas
    #
    topFrame = ControlFrame(rootFrame, hub, dbFile, width=WIDTH-4,
      height=controlHeight, bd=1, relief=SUNKEN)
    topFrame.grid_propagate(False)
    topFrame.grid(column=1, row=1, columnspan=2)
    hub.addControlFrame(topFrame)
    
    displayFrame = ScrollDisplayFrame(rootFrame, hub,
      width=WIDTH-MAIN-4, height=centerHeight, 
      bd=1, relief=SUNKEN)
    displayFrame.grid_propagate(False)
    displayFrame.grid(column=2, row=2)
    hub.addDisplayFrame(displayFrame.frame)
    displayFrame.frame.addSimplot(simplot)
    
    nodeFrame = ScrollNodeFrame(rootFrame, hub, dbFile, width=MAIN-4,
      height=centerHeight, bd=1, relief=SUNKEN)
    nodeFrame.grid_propagate(False)
    nodeFrame.grid(column=1, row=2)
    hub.addNodeFrame(nodeFrame.frame)
    
#     statusFrame = StatusFrame(rootFrame, hub, width=WIDTH-4,
#       height=statusHeight, bd=1, relief=SUNKEN)
#     statusFrame.grid_propagate(False)
#     statusFrame.grid(column=1, row=3, columnspan=2)
#     hub.addStatusFrame(statusFrame)
    
    #
    #
    #
    try:
        root.mainloop()
    except KeyboardInterrupt:
        pass

