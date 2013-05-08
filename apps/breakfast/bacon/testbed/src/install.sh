#!/bin/bash
if [ $# -lt 1 ]
then
  echo "Usage: $0 <map> [option files]"
  exit 1
fi
MAP=$1
shift 1

make bacon2 $(paste -d ' ' $@)

for i in $(grep -v '#' $MAP | awk '{print $2}')
do
  make bacon2 reinstall,$i wpt,$MAP
done
