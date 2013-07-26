#!/usr/bin/env python
from autoPush.decoders import Decoder
import sqlite3
import struct
import cx.constants

class BaconSettings(Decoder.Decoder):
    @classmethod 
    def recordType(cls):
        return 0x17
    
    def unpack(self, source, cookie, data):
        ds = ''.join([chr(v) for v in data])
        header = ds[0:7]
        body = ds[7:]
        (rc, ts, offset) = struct.unpack('<HLB', header)
        return (source, cookie, rc, ts, offset, buffer(body))

    def insert(self, source, cookie, data):
        if not self.connected:
            self.connection = sqlite3.connect(self.dbName)
        q ='''INSERT OR IGNORE INTO bacon_settings 
           (node_id, cookie, rc, ts, offset, data, barcode_id, bacon_interval, toast_interval) values 
           (?,       ?,      ?,  ?,  ?,      ?,    '',         ?,              ?)'''
        t = self.unpack(source, cookie, data)
        (node_id, cookie, rc, ts, offset, tlv ) = t
        print "Decoded Bacon Settings"
        self.connection.execute(q, 
          (node_id, cookie, rc, ts, offset, tlv, 
           cx.constants.DEFAULT_SAMPLE_INTERVAL,
           cx.constants.DEFAULT_SAMPLE_INTERVAL))
        #if this is the second half, join em up
        if offset == 64:
            pass
            chunks = self.connection.execute('''select data from
            bacon_settings 
            WHERE node_id = ? and rc=? and ts=? 
            ORDER BY offset''', 
            (node_id, rc, ts)).fetchall()
            print chunks
            if (len(chunks) == 2):
                tlv = reduce(lambda l,r: l[0]+r[0], chunks)
                for (tag, length, value) in Decoder.tlvIterator(tlv):
                    print "next (t,l,v)", hex(tag), length, ' '.join([hex(ord(c)) for c in value])
                    if tag == cx.constants.SS_KEY_GLOBAL_ID:
                        baconIDText = Decoder.toHexStr(buffer(value))
                        self.connection.execute('''UPDATE
                        bacon_settings SET barcode_id = ? WHERE
                        node_id=? and rc = ? and ts=?''',
                          (baconIDText, node_id, rc, ts))
                    if tag == cx.constants.SS_KEY_BACON_SAMPLE_INTERVAL:
                        (baconSampleInterval,) = struct.unpack('>L', value)
                        self.connection.execute('''UPDATE bacon_settings
                        SET bacon_interval = ? 
                        WHERE node_id=? and rc=? and ts=?''',
                        (baconSampleInterval, node_id, rc, ts))
                    if tag == cx.constants.SS_KEY_TOAST_SAMPLE_INTERVAL:
                        (toastSampleInterval,) = struct.unpack('>L', value)
                        self.connection.execute('''UPDATE bacon_settings
                        SET toast_interval = ? 
                        WHERE node_id=? and rc=? and ts=?''',
                        (toastSampleInterval, node_id, rc, ts))

        self.connection.commit()
        self.connection.close()

