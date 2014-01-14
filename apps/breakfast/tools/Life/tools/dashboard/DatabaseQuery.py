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


import sqlite3

import tools.cx.constants as constants
import time
import traceback

class DatabaseQuery(object):

    def __init__(self, dbName):
        self.dbName = dbName
        self.connected = False
        print "DBQ %s"%(dbName)
        

    def __del__(self):
        if self.connected == True:
            self.cursor.close()
            self.connection.close()
            
            print "closing connection" 

    def getLastDownloadResults(self, masterId):
        query = ''' SELECT lastDownload.master_id, reachedCount.cnt, allCount.cnt
          FROM 
          (select master_id, max(cookie) as cookie FROM active_period WHERE master_id = ? GROUP BY master_id) as lastDownload
          JOIN 
          (select master_id, cookie, count(*) as cnt FROM network_membership GROUP BY master_id, cookie) as allCount
          ON lastDownload.master_id = allCount.master_id AND lastDownload.cookie = allCount.cookie
          JOIN 
          (select master_id, cookie, count(*) as cnt FROM network_membership WHERE distance < 255 GROUP BY master_id, cookie) as reachedCount
          ON lastDownload.master_id = reachedCount.master_id AND lastDownload.cookie = reachedCount.cookie
        '''
        
        try:
            c = sqlite3.connect(self.dbName)
            ret = c.execute(query, (masterId,)).fetchone()
        except:
            traceback.print_exc()
            
        if not ret:
            ret = (0, 0, 0)
        return ret

    def getNodesByRole(self, role):
        query = '''
          SELECT node_status.node_id, 
            barcode_id, 
            sampleInterval,
            subnetChannel,
            role
          FROM last_status
          JOIN node_status 
            ON last_status.node_id = node_status.node_id 
            AND last_status.ts = node_status.ts
          WHERE node_status.role = ?'''
        
        # sqlite connections can only be used from the same threads they are established from
        if self.connected == False:
            self.connected == True
            # raises sqlite3 exceptions
            self.connection = sqlite3.connect(self.dbName)
            self.connection.text_factory = str
            self.cursor = self.connection.cursor()
        
        output = {}
        
        try:
            self.cursor.execute(query,
              (constants.ROLE_ROUTER,))

            for row in self.cursor:
                nodeId  = row[0]
                barcode = row[1]
                sampleInterval = row[2]
                channel = row[3]
                output[channel] = output.get(channel, []) + [(barcode,
                  nodeId, sampleInterval)]
        except:
            traceback.print_exc()
        return output
        

    def getRouters(self):
        """
        Get list of routers in range of basestation.
        """
        return self.getNodesByRole(constants.ROLE_ROUTER)



    def getLeafs(self):
        """
        Get the latest downloaded settings from all the Nodes in the network.
        This is complimentary to what is found in the network.settings file.
        """
        return self.getNodesByRole(constants.ROLE_LEAF)
    
    def getSiteMap(self):
        site = {}
        routers = self.getRouters()
        for channel in routers:
            channelMap = site.get(channel,{})
            channelMap['routers'] = routers[channel]
            site[channel] = channelMap

        leafs = self.getLeafs()
        for channel in leafs:
            channelMap = site.get(channel,{})
            channelMap['leafs'] = leafs[channel]
            site[channel] = channelMap
        return site

    def getSettings(self):
        query = '''
          SELECT node_status.node_id, 
            barcode_id, 
            sampleInterval,
            subnetChannel,
            role
          FROM last_status
          JOIN node_status 
            ON last_status.node_id = node_status.node_id 
            AND last_status.ts = node_status.ts'''
        
        # sqlite connections can only be used from the same threads they are established from
        if self.connected == False:
            self.connected == True
            # raises sqlite3 exceptions
            self.connection = sqlite3.connect(self.dbName)
            self.connection.text_factory = str
            self.cursor = self.connection.cursor()
        
        output = {}
        
        try:
            self.cursor.execute(query)

            for row in self.cursor:
                nodeId  = row[0]
                barcode = row[1]
                sampleInterval = row[2]
                channel = row[3]
                role = row[4]
                output[barcode] = (nodeId, sampleInterval, channel, role)
        except:
            traceback.print_exc()
        return output

    def getMissingCookies(self):
        """
        Get the missing cookie values for each node.
        """

        SORT_COOKIE_SQL = '''CREATE TEMPORARY TABLE sorted_flash AS 
             SELECT cookie_table.node_id as node_id, 
               cookie, nextCookie, retry, barcode_id
             FROM cookie_table 
             JOIN last_status 
               ON cookie_table.node_id = last_status.node_id
             JOIN node_status 
               ON node_status.node_id = last_status.node_id 
                  AND node_status.ts = last_status.ts
             ORDER BY cookie_table.node_id, cookie'''

        MISSING_ORDER_SIZE_SQL = '''SELECT l.barcode_id, 
              l.cookie,
              (r.cookie - l.nextCookie -1) as missing
            FROM sorted_flash l
            JOIN sorted_flash r
            ON l.node_id = r.node_id
              AND l.ROWID +1 = r.ROWID
              AND missing > 6
              AND l.retry < 5
              ORDER BY l.node_id, missing desc'''
        
        # sqlite connections can only be used from the same threads they are established from
        if self.connected == False:
            self.connected == True
            # raises sqlite3 exceptions
            self.connection = sqlite3.connect(self.dbName)
            self.connection.text_factory = str
            self.cursor = self.connection.cursor()
        
        output = {}
        
        # sort the flash table by cookie values (ascending)
        # and find missing segments by comparing lengths and cookies
        try:
            self.cursor.execute(SORT_COOKIE_SQL)
            self.cursor.execute(MISSING_ORDER_SIZE_SQL)
            
            for row in self.cursor:
                barcode = row[0]
                cookie = row[1]
                missing = row[2]
                
                if barcode in output:
                    list = output[barcode]
                else:
                    list = []
                    
                list.append((cookie, missing))
                output[barcode] = list
        except:
            traceback.print_exc()
        return output

    def getCookieRate(self):
        """
        Get the data generation rate for each node in bytes/seconds.
        """
        
        query = '''
                SELECT a.barcode_id, a.ts, a.writeCookie, b.ts, b.writeCookie 
                FROM 
                    (
                        SELECT barcode_id, MAX(ts) AS ts, writeCookie
                        FROM node_status
                        GROUP BY barcode_id 
                    ) a 
                    JOIN 
                    (
                        SELECT barcode_id, ts, writeCookie
                        FROM node_status
                        ORDER BY barcode_id ASC, ts DESC
                    ) b
                    ON a.barcode_id = b.barcode_id 
                    AND a.ts > b.ts 
                    AND a.writeCookie <> b.writeCookie
                GROUP BY a.barcode_id
                '''   

        # sqlite connections can only be used from the same threads they are established from
        if self.connected == False:
            self.connected == True
            # raises sqlite3 exceptions
            self.connection = sqlite3.connect(self.dbName)
            self.connection.text_factory = str
            self.cursor = self.connection.cursor()

        output = {}
        try:
            self.cursor.execute(query)        
            
            for row in self.cursor:
                barcode = row[0]
                currentTs = row[1]
                currentCookie = row[2]
                oldTs = row[3]
                oldCookie = row[4]
                
                if currentTs > oldTs and currentCookie > oldCookie:
                    rate = (currentCookie - oldCookie) / (currentTs - oldTs)
                    
                    output[barcode] = (currentCookie, rate)
        except:
            traceback.print_exc()
        
        return output
    
    def getMultiplexers(self):
        """
        Get the current view of the network, i.e., what Nodes are available, 
        what Multiplexers do they have attached, and what sensor types are 
        connected to the Multiplexers.
        """
        
        query = '''
          SELECT bacon_settings.barcode_id, tc.node_id,
          tc.reboot_counter, tc.time, tc.cookie, tc.toast_id,
          sc.channel_number, sc.sensor_type, sc.sensor_id
          FROM (
          SELECT lc.node_id, lc.toast_id, 
            max(lc.cookie, coalesce(lb.cookie, -1), coalesce(ld.cookie, -1)) as cookie
          FROM last_connection lc 
          LEFT JOIN last_disconnection ld
            ON lc.node_id = ld.node_id 
               AND lc.toast_id = ld.toast_id
          LEFT JOIN last_bs lb
            ON lc.node_id = lb.node_id
            ) lr 
          JOIN toast_connection tc 
            ON lr.node_id = tc.node_id 
               AND lr.cookie = tc.cookie
          JOIN sensor_connection sc 
            ON sc.node_id = tc.node_id AND sc.cookie = tc.cookie
          JOIN last_bs on tc.node_id = last_bs.node_id
          JOIN bacon_settings on last_bs.node_id = bacon_settings.node_id AND
          last_bs.cookie = bacon_settings.cookie'''

        # sqlite connections can only be used from the same threads they are established from
        if self.connected == False:
            self.connected == True
            # raises sqlite3 exceptions
            self.connection = sqlite3.connect(self.dbName)
            self.connection.text_factory = str
            self.cursor = self.connection.cursor()

        output = {}
        try:
            self.cursor.execute(query)        
            #sql query return 1 row per currently-connected sensor
            #we want to put this into a nested set of maps like this:
            #{
            #  bacon_barcode:{
            #    toast_barcode:{
            #      channel:(sensor_type, sensor_barcode)}
            #  }
            #}
            for row in self.cursor:
                baconBar = row[0]
                toastBar = row[5]
                cn = row[6]
                st = row[7]
                sid = row[8]
                output[baconBar] = output.get(baconBar, {})
                output[baconBar][toastBar] = output[baconBar].get(toastBar, {})
                output[baconBar][toastBar][cn]=(st, sid)
        except:
            traceback.print_exc()
        
        return output


    def getPlex(self, plex):
        """ Get information about multiplexer.
        """
        query = """ SELECT channel_number, sensor_type, sensor_id
                    FROM 
                    (
                        SELECT node_id, max(cookie) AS cookie
                        FROM toast_connection 
                        WHERE toast_id = '%s'
                    ) AS c
                    LEFT JOIN sensor_connection AS d 
                    ON c.node_id = d.node_id AND c.cookie = d.cookie """ % plex
        
        # sqlite connections can only be used from the same threads they are established from
        if self.connected == False:
            self.connected == True
            # raises sqlite3 exceptions
            self.connection = sqlite3.connect(self.dbName)
            self.connection.text_factory = str
            self.cursor = self.connection.cursor()

        #output = [("",""), ("",""), ("",""), ("",""), ("",""), ("",""), ("",""), ("","")]
        output = [(None,None), (None,None), (None,None), (None,None), (None,None), (None,None), (None,None), (None,None)]
        
        try:
            self.cursor.execute(query)
            
            for row in self.cursor:
                if row[0] is not None:
                    channel = int(row[0])
                    output[channel] = (hex(row[1]), hex(row[2]))
        except:
            traceback.print_exc()
        
        return output

    def contactSummary(self):
        now = time.time()
        query ='''
        SELECT y.node_id, y.barcode_id, coalesce(x.lastSampleTime, 0),
          y.lastContact, coalesce(batteryVoltage, 0)
        FROM (
          SELECT last_bs.node_id, barcode_id,
            max(unixTS) as lastContact
          FROM base_reference
          JOIN last_bs 
            ON base_reference.node1 = last_bs.node_id
          JOIN bacon_settings 
            ON last_bs.node_id = bacon_settings.node_id
            AND last_bs.cookie = bacon_settings.cookie
          GROUP BY base_reference.node1, barcode_id) y 
        LEFT JOIN (
          SELECT 
            node_id,
            barcode_id,
            max(ts) as lastSampleTime
          FROM bacon_sample_final
          GROUP BY node_id, 
            barcode_id ) x
        ON y.barcode_id = x.barcode_id
        LEFT JOIN bacon_sample_final 
          ON x.node_id=bacon_sample_final.node_id 
            AND x.lastSampleTime = bacon_sample_final.ts
        '''
        if self.connected == False:
            self.connected == True
            # raises sqlite3 exceptions
            self.connection = sqlite3.connect(self.dbName)
            self.connection.text_factory = str
            self.cursor = self.connection.cursor()
            
        output = []
            
        try:
            output = self.cursor.execute(query).fetchall()
        except:
            traceback.print_exc()
        
        return output

if __name__ == '__main__':
    db = DatabaseQuery("database0.sqlite")
    print "Leafs:",db.getLeafs()
    print "Routers:",db.getRouters()
    print "LDR:",db.getLastDownloadResults(61)
    print "CS:", db.contactSummary()
    
#     network = db.getNetwork()
# 
#     #for node in network:
#         #print node, network[node]
#         #for plex in network[node]:
#         #    print node, plex
# 
#     settings = db.getSettings()
# 
#     for i, n in enumerate(sorted(settings.iterkeys())):
#         print i, n
#     
#     #for node in settings:
#     #    print node, settings[node]
#     
