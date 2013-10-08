#!/bin/bash
testDuration=$((60 * 60))

while true
do
  #power adjust
  for pa in 1
  do
    #tx power
    for txp in 0x2D 
    do
      #enable auto-sender
      for eas in 0
      do
        #frames per slot
        for fps in 30
        do
          #data rate
          for dr in 0
          do
            #max cts miss threshold
            for mct in 4
            do
              #debug level stats-radio. DL_NONE disables radio state
              # change logging
              for dlsr in DL_INFO DL_NONE
              do
                ./testbed.sh eas $eas fps $fps dr $dr rp $txp lp $txp \
                  pa $pa mct $mct dlsr $dlsr gc 128
                sleep $testDuration
                pushd .
                cd ~/tinyos-2.x/apps/Blink
                ./burn map.all
                sleep 60
                popd
              done
            done
          done
        done
      done
    done
  done
done
