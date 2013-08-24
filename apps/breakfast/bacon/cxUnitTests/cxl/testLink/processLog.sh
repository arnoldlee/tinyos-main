#!/bin/bash
if [ $# -lt 2 ]
then 
  echo "Usage: $0 <logFile> <dbFile>" 1>&2
  exit 1
fi
log=$1
db=$2

dos2unix $log

echo "Processing $log: RX"
#1             2  3  4   5  6 7  8    9  10   11
#ts            n  -  sn  hc t pl sfds pa minP maxP
#1377284263.55 32 RX 336 10 6 1  0    0  3    2d
pv $log | grep ' RX ' | awk '(NF == 11){print $1, $2, $4, $5, $6, $7, $8, $9, $10, $11, 1}' > rx.tmp

echo "Processing $log: TX"
#1             2  3  4   5 6  7    8  9   10  11
#ts            n  -  sn  e t  pl sfds pa minP maxP
#1377284976.97 0  TX 273 0 6  1    0  1  3    2d
pv $log | grep ' TX ' | awk '(NF == 11){print $1, $2, $4, $6, $7, $8, $9, $10, $11}' > tx.tmp

sqlite3 $db <<EOF
.separator ' '
drop table if exists RX;
CREATE TABLE RX (
  ts FLOAT,
  node INTEGER,
  sn INTEGER,
  hc INTEGER,
  tn INTEGER,
  pl INTEGER,
  sfds INTEGER,
  pa INTEGER,
  minP TEXT,
  maxP TEXT,
  r INTEGER
);
SELECT "Loading RX";
.import 'rx.tmp' RX

drop table if exists TX;
CREATE TABLE TX (
  ts FLOAT,
  node INTEGER,
  sn INTEGER,
  tn INTEGER,
  pl INTEGER,
  sfds INTEGER,
  pa INTEGER,
  minP TEXT,
  maxP TEXT
);
SELECT "Loading TX";
.import 'tx.tmp' TX

DROP TABLE IF EXISTS nodes;
CREATE TABLE nodes as 
SELECT distinct node from TX UNION
SELECT distinct node from RX;

DROP TABLE IF EXISTS setups;
CREATE TABLE setups AS
SELECT distinct tn, node as origin, pl, sfds, pa, minP, maxP FROM TX;

SELECT "Finding drops";
DROP TABLE IF EXISTS RXM;
CREATE TABLE RXM as
SELECT tx.tn, tx.sn, nodes.node, coalesce(rx.r, 0) as r
FROM TX 
JOIN nodes
LEFT JOIN rx ON tx.tn = rx.tn AND tx.sn = rx.sn AND rx.node = nodes.node;

SELECT "Aggregating results";
DROP TABLE IF EXISTS AGG;
CREATE TABLE AGG AS
SELECT prr.tn as tn, prr.node as node, prr.prr as prr, hopCount.avgHC
as hopCount
FROM 
(SELECT tn, node, (1.0*sum(r))/count(r) as prr FROM rxm GROUP BY tn,
node) prr
JOIN 
(SELECT tn, node, avg(hc) as avgHC FROM rx GROUP BY tn, node) hopCount
ON hopCount.tn = prr.tn AND hopCount.node = prr.node;

EOF
