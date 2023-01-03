#!/bin/bash 
# Sends image process request to queue
for ((i=0; i<10000; i++))
do
  printf "x%02d\n" "$i"
done > /dev/tcp/127.0.0.1/$IN_PORT