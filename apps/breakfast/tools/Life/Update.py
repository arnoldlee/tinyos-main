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
import subprocess
import os
import datetime

class MessageWindow(object):
    def __init__(self, parent, logFile):
        self.logFile = logFile
        self.messageFrame = Frame(parent)
        self.messageText = Text(self.messageFrame, height=10, width=70,
          background='white')

        self.scroll = Scrollbar(self.messageFrame)
        self.messageText.configure(yscrollcommand=self.scroll.set)
        self.scroll.configure(command = self.messageText.yview)

        self.scroll.pack(side="right", fill="y")

        self.updateButton = Button(self.messageFrame, 
          text="Update", command = self.update)
        self.messageText.pack(side="left", fill="both", expand=True)
        self.updateButton.pack(side="bottom")
        self.messageFrame.pack(fill="both", expand=True)

    def update(self):
        print "Updating"
        self.updateButton.config(text="UPDATING", bg="red",
          state=DISABLED)
        self.addMessage("Updating\n")
        sp = subprocess.Popen("git pull", shell=True,
          stdout=subprocess.PIPE, 
          stderr=subprocess.STDOUT)
        (out, err) = sp.communicate()
        for line in out:
            self.addMessage(line)
        self.updateButton.config(text="Update", bg="gray",
          state=NORMAL)


    def addMessage(self, message):
        self.messageText.insert(END, message)
        self.logFile.write(message)
        self.messageText.yview(END)

    def __del__(self):
        self.logFile.close()

if __name__ == '__main__':
    root = Tk()
    root.title("Updater")
    root.bind("<Alt-F4>", root.quit)
    root.bind('<Control-c>', root.quit)
    root.protocol("WM_DELETE_WINDOW", root.quit)
    logDir ='logs'
    if not os.path.isdir(logDir):
        os.mkdir(logDir)
    now_str = datetime.datetime.now().strftime("%Y%m%dT%H%M%S")
    logFile = open(os.path.join(logDir, "%s.update.log"%(now_str,)), 'w')
    mw = MessageWindow(root, logFile)
    try:
        root.focus_set()
        root.mainloop()
    except KeyboardInterrupt:
        pass
