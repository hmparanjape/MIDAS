#!/bin/bash -eu
source ${HOME}/.MIDAS/paths
${PFDIR}/SHM.sh
RC=${?}
if [[ RC != 0 ]]
then
  echo "RC == 0."
fi

if [[ $1 == 32 ]]
then
  cp Spots.bin Data.bin nData.bin ExtraInfo.bin /dev/shm
 # scp Spots.bin Data.bin nData.bin ExtraInfo.bin puppy21:/dev/shm
 # scp Spots.bin Data.bin nData.bin ExtraInfo.bin puppy22:/dev/shm
 # scp Spots.bin Data.bin nData.bin ExtraInfo.bin puppy37:/dev/shm
 # scp Spots.bin Data.bin nData.bin ExtraInfo.bin puppy39:/dev/shm
 # scp Spots.bin Data.bin nData.bin ExtraInfo.bin puppy41:/dev/shm
 # scp Spots.bin Data.bin nData.bin ExtraInfo.bin puppy43:/dev/shm
 # scp Spots.bin Data.bin nData.bin ExtraInfo.bin puppy44:/dev/shm
fi
