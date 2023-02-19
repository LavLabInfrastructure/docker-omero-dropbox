#!/bin/bash
# queues images in a given directory
regex=$(echo $WSI_EXTENSIONS | sed 's/|/\\|/g')
[[ $1 =~ \*$ ]] && /docker/log.sh WARN "Wildcard did not expand! Could not find WSIs in directory: '/in/$1'" && exit 0
find /in/$1 -iregex $regex |
    while read file; do
        # ignore PROCESSING directory in project name
        /docker/queueImage.sh $file ${1#.PROCESSING/}
    done