#!/bin/bash
# adds image to redis queue
/docker/log.sh INFO "Added to Queue: $1"

# if input is already queued, ignore it. 
[[ ! -z $(redis-cli lrange queue 0 -1 | grep \'$1\'; exit 0) ]] && continue

# if priority import, prepend, else, append
[[ "${a##*/}" =~ "PRIORITY_" ]] &&
    redis-cli lpush queue "$1 $2" 1> /dev/null 2>& 1 ||
    redis-cli rpush queue "$1 $2" 1> /dev/null 2>& 1