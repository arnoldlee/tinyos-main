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


import tools.cx.Phoenix as Phoenix
import sys
import sqlite3
import os

queries=[
  #connect toast_samples to their matching toast_connection's
  '''DROP TABLE IF EXISTS ss0''',
  '''CREATE TEMPORARY TABLE ss0 AS
  SELECT ts.node_id, ts.reboot_counter, ts.cookie as sample_cookie,
    tc.cookie as connection_cookie
  FROM toast_sample ts
    JOIN toast_connection tc
  ON ts.node_id = tc.node_id 
    AND ts.reboot_counter = tc.reboot_counter
    AND ts.toast_id = tc.toast_id 
    AND tc.cookie < ts.cookie''',

  #remove duplicate entries resulting from multiple toast connections
  '''DROP TABLE IF EXISTS ss1''',
  '''CREATE TEMPORARY TABLE ss1 AS
  SELECT node_id, reboot_counter, sample_cookie, 
    max(connection_cookie) as connection_cookie
  FROM ss0
  GROUP BY node_id, reboot_counter, sample_cookie''',
  
  #find matching bacon barcodes
  '''DROP TABLE IF EXISTS ss2''',
  '''CREATE TEMPORARY TABLE ss2 AS
  SELECT ss1.node_id, ss1.sample_cookie as sample_cookie, bse.cookie as settings_cookie
  FROM ss1 
  JOIN bacon_settings as bse 
    ON ss1.reboot_counter=bse.rc AND bse.cookie < ss1.sample_cookie
    AND ss1.node_id = bse.node_id
  WHERE bse.barcode_id != ""''',

  #drop duplicate bacon barcodes
  '''DROP TABLE IF EXISTS ss3''',
  '''CREATE TEMPORARY TABLE ss3 AS
  SELECT node_id, sample_cookie, 
    max(settings_cookie) as settings_cookie
  FROM ss2
  GROUP BY node_id, sample_cookie''',

  #normalize to sensor samples + raw timing info
  '''DROP TABLE IF EXISTS sensor_sample_flat''',
  '''CREATE TABLE sensor_sample_flat AS
  SELECT sc.sensor_type, sc.sensor_id, sc.channel_number,
    ts.node_id, ts.reboot_counter, ts.base_time,  
    ts.toast_id, bs.barcode_id as bacon_id,
    ss.sample
  FROM sensor_sample ss 
    JOIN toast_sample ts 
      ON ss.node_id = ts.node_id AND ss.cookie = ts.cookie
    JOIN ss1 
      ON ss.node_id = ss1.node_id AND ss.cookie=ss1.sample_cookie
    JOIN toast_connection tc
      ON ss1.connection_cookie = tc.cookie AND ss1.node_id = tc.node_id
    JOIN sensor_connection sc
      ON sc.cookie = tc.cookie AND
      sc.channel_number = ss.channel_number
    JOIN ss3
      ON ss3.sample_cookie = ss.cookie AND ss3.node_id = ss.node_id
    JOIN bacon_settings bs
      ON ss3.node_id = bs.node_id AND ss3.settings_cookie=bs.cookie''',
  #associate bacon samples to bacon_settings
  '''DROP TABLE IF EXISTS bs0''',
  '''CREATE TEMPORARY TABLE bs0 AS
  SELECT bsa.node_id, bsa.cookie as sample_cookie, bse.cookie as settings_cookie
  FROM bacon_sample as bsa
  JOIN bacon_settings as bse 
    ON bsa.reboot_counter=bse.rc AND bse.cookie < bsa.cookie
    AND bsa.node_id = bse.node_id
  WHERE bse.barcode_id != ""''',
  #remove duplicate bacon_settings mappings
  '''DROP TABLE IF EXISTS bs1''',
  '''CREATE TEMPORARY TABLE bs1 AS
  SELECT node_id, sample_cookie, max(settings_cookie) as settings_cookie
  FROM bs0
  GROUP BY node_id, sample_cookie''',
  #map to barcodes
  '''DROP TABLE IF EXISTS bacon_sample_flat''',
  '''CREATE TABLE bacon_sample_flat AS
  SELECT bsa.*, bse.barcode_id
  FROM bacon_sample bsa
  JOIN bs1 
    ON bsa.cookie = bs1.sample_cookie AND bsa.node_id = bs1.node_id
  JOIN bacon_settings bse
    ON bse.cookie = bs1.settings_cookie AND bse.node_id =
    bs1.node_id ''',
  #apply timing fits and convert bacon samples to voltage
  '''DROP TABLE IF EXISTS bacon_sample_final''',
  '''CREATE TABLE bacon_sample_final AS
  SELECT bsf.barcode_id, bsf.node_id, bsf.cookie,  
    (base_time*beta + alpha) as ts, 
    2.0*(battery/4096.0)*2.5 as batteryVoltage,
    (light/4096.0)*2.5 as lightVoltage,
    (thermistor/4096.0)*2.5 as thermistorVoltage,
    fits.r_sq as tsQuality
  FROM bacon_sample_flat bsf
  JOIN fits 
    ON fits.node1=bsf.node_id AND fits.rc1=bsf.reboot_counter
       AND fits.node2 is NULL and fits.rc2 is NULL''',
  #apply timing fits and convert sensor samples to voltage
  '''DROP TABLE IF EXISTS sensor_sample_final''',
  '''CREATE TABLE sensor_sample_final AS
  SELECT ssf.bacon_id, ssf.toast_id, ssf.sensor_type, ssf.channel_number, ssf.sensor_id, 
    (base_time*beta + alpha) as ts,
    (sample/4096.0)*2.5 as voltage,
    fits.r_sq as tsQuality
  FROM sensor_sample_flat ssf
  JOIN fits 
    ON fits.node1=ssf.node_id AND fits.rc1=ssf.reboot_counter
       AND fits.node2 is NULL AND fits.rc2 is NULL''',
  '''DROP TABLE IF EXISTS current_sensors''',
  '''CREATE TABLE current_sensors AS
      SELECT bacon_settings.barcode_id as bacon_barcode, 
        tc.node_id as node_id,
        tc.reboot_counter as rc, 
        tc.time as time, 
        tc.cookie as cookie, 
        tc.toast_id as toast_barcode,
        sc.channel_number as channel_number, 
        sc.sensor_type as sensor_type, 
        sc.sensor_id as sensor_id
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
      last_bs.cookie = bacon_settings.cookie''',
    '''DROP TABLE IF EXISTS current_sensors_final''',
    '''CREATE TABLE current_sensors_final AS
       SELECT bacon_barcode, toast_barcode, 
          (time*beta+alpha) as ts,
          channel_number, sensor_type, sensor_id,
          fits.r_sq as tsQuality
       FROM current_sensors 
       LEFT JOIN fits
       ON fits.node1 = current_sensors.node_id
          AND fits.rc1 = current_sensors.rc''']

def deNormalize(dbName, progCallback=None):
    c = sqlite3.connect(dbName)
    try:
        for (i,q) in enumerate(queries):
            if progCallback:
                progCallback("Formatting data step %u/%u\n"%(i, len(queries)))
            c.execute(q)
    except:
        e = sys.exc_info()[0]
        print >>sys.stderr, "Exception while de-normalizing data", e
    else:
        c.commit()

def dump(dbName, baseDir, progCallback=None, sep=','):
    #baseDir/internal.csv
    if not os.path.isdir(baseDir):
        os.mkdir(baseDir)
    internalCols= ["bacon_id", "unixTS", "isoTS", "date", "time", "batteryVoltage",
      "lightVoltage", "thermistorVoltage", "tsQuality"]
    externalCols= ["sensor_type", "bacon_id", "toast_id", 
      "sensor_channel", "sensor_id", "unixTS", "isoTS", "date", "time", "voltage", "tsQuality"]
    sensorCols = ["bacon_id", "toast_id", "unixTS", "isoTS", "date",
      "time", "channel", "sensorType", "sensorId", "tsQuality"]
    c = sqlite3.connect(dbName)
    if progCallback:
        progCallback("Dumping internal sensors\n")
    with open(os.path.join(baseDir, 'internal.csv'), 'w') as f:
        with c:
            q= ''' SELECT barcode_id, ts, 
              datetime(ts, 'unixepoch', 'localtime'), 
              date(ts, 'unixepoch', 'localtime'), 
              time(ts, 'unixepoch', 'localtime'), 
              batteryVoltage, lightVoltage, thermistorVoltage, tsQuality
            FROM bacon_sample_final ORDER BY barcode_id, ts'''
            f.write(sep.join(internalCols) +'\n')
            for (bacon_id, unixTS, isoTS, date, time, bv, lv, tv, tsq) in c.execute(q).fetchall():
                #f.write(sep.join([str(col) for col in row]) + '\n')
                f.write(sep.join([bacon_id, "%.2f"%unixTS, isoTS,
                date, time, "%.4f"%bv, "%.4f"%lv, "%.4f"%tv, "%.4f"%tsq])+"\n")

    #baseDir/<sensorType>.csv
    with c:
        for (st,) in c.execute('''SELECT distinct sensor_type from sensor_sample_final''').fetchall():
            if progCallback:
                progCallback("Dumping sensor data for type %u\n"%st)
            with open(os.path.join(baseDir, 'sensorType_'+str(st)+'.csv'), 'w') as f:
                f.write(sep.join(externalCols)+'\n')
                q= '''SELECT sensor_type, bacon_id, toast_id,
                channel_number+1, sensor_id, ts, 
                datetime(ts, 'unixepoch', 'localtime') as isoTS, 
                date(ts, 'unixepoch', 'localtime'), 
                time(ts, 'unixepoch', 'localtime'), 
                voltage, tsQuality
                FROM sensor_sample_final WHERE sensor_type=? ORDER BY
                bacon_id, toast_id, sensor_id, ts'''
                for (sensor_type, bacon_id, toast_id, sensor_channel, 
                  sensor_id, unixTS, isoTS, date, time, voltage, tsq) in c.execute(q, (st,)).fetchall():
                    f.write(sep.join([str(sensor_type), bacon_id,
                    toast_id, str(sensor_channel), str(sensor_id), 
                    "%.2f"%unixTS, isoTS, date, time, "%.4f"%voltage,
                    "%.4f"%tsq])+'\n')

    if progCallback:
        progCallback("Dumping sensor listing\n")
    with c:
        q = '''SELECT bacon_barcode, toast_barcode, 
                ts as unixTS,
                datetime(ts, 'unixepoch', 'localtime') as isoTS,
                date(ts, 'unixepoch', 'localtime'), 
                time(ts, 'unixepoch', 'localtime'), 
                channel_number+1,
                sensor_type, sensor_id,
                tsQuality
               FROM current_sensors_final'''
        with open(os.path.join(baseDir, 'sensors.csv'), 'w') as f:
            f.write(sep.join(sensorCols)+'\n')
            for (bacon_id, toast_id, unixTS, isoTS, date, time, channel, sensorType, sensorId, tsq) in c.execute(q).fetchall():
                f.write(sep.join([bacon_id, toast_id, "%.2f"%unixTS, isoTS, date,
                  time, str(channel), str(sensorType), hex(sensorId),
                  "%.4f"%tsq])+'\n')



def dumpCSV(dbName, baseDir='data', progCallback=None):
    print "Dumping from %s to %s"%(dbName, baseDir)
    print "Generating timestamp information"
    Phoenix.phoenix(dbName, progCallback=progCallback)
    print "formatting data"
    deNormalize(dbName, progCallback=progCallback)
    print "dumping to .csv files"
    dump(dbName, baseDir, progCallback=progCallback)
    

if __name__ == '__main__':
    dbName = 'database0.sqlite'
    baseDir = 'data'
    if len(sys.argv) > 1:
        dbName = sys.argv[1]
    if len(sys.argv) > 2:
        baseDir = sys.argv[2]
    dumpCSV(dbName, baseDir)
