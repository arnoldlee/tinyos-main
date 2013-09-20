#!/usr/bin/env python

import threading

from DatabaseInit import DatabaseInit
from DatabaseInsert import DatabaseInsert
from DatabaseMissing import DatabaseMissing

import time


class Database(object):

    def __init__(self, rootName='database'):
        init = DatabaseInit(rootName)
        self.dbName = init.getName()

        self.insert = DatabaseInsert(self.dbName)
        self.missing = DatabaseMissing(self.dbName)
        self.decoders = {}
        

    def addDecoder(self, decoderClass):
        self.decoders[decoderClass.recordType()] = decoderClass(self.dbName)
        return self.decoders[decoderClass.recordType()]


    def insertRecord(self, source, record):
        #print "Database.insertRecord()", threading.current_thread().name
        
        (cookie, nextCookie, length, recordType, data) = record            
        
        print "Database.insertRecord()", source, cookie, nextCookie, length, recordType, data
        
        self.insert.insertFlash(source, cookie, nextCookie, length)        
        if recordType in self.decoders:
            self.decoders[recordType].insert(source, cookie, data)

            ##calcLen = cookieVal - self.oldCookieVal - 1
            ##print "# %X" % cookieVal, calcLen, self.oldLenVal
            ##if calcLen != self.oldLenVal:
            ##    print '============================================='
            ##
            ## print lenVal, recordData
            ##self.oldCookieVal = cookieVal
            ##self.oldLenVal = lenVal
        else: 
            print "No decoder for 0x%x"%recordType

    def insertRaw(self, source, message):
        self.insert.insertRaw(source, message)
#         print "RAW",message.addr, time.time(), message.am_type, message.data

    def findMissing(self, incrementRetries=True):
        
        return self.missing.findMissing(incrementRetries)
        


if __name__ == '__main__':

    db = Database()

    missing_list = db.findMissing()

    for rec in missing_list:
        print rec
    
    






