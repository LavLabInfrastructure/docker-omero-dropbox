#!/bin/bash
# adds image to redis queue

# if input is already queued or running, ignore it. 
[[ ! -z $(redis-cli lrange queue 0 -1 | grep ${1##*/}; exit 0) ]] && 
    /docker/log.sh WARN "Image with same name is already running! Ignoring: $1" && 
    exit 1
[[ ! -z $(redis-cli lrange running 0 -1 | grep ${1##*/}; exit 0) ]] && 
    /docker/log.sh WARN "Image with same name is already queued! Ignoring: $1" && 
    exit 1
    
# if priority import, prepend, else, append
/docker/log.sh INFO "Added to Queue: $1"
[[ "${a##*/}" =~ "PRIORITY_" ]] &&
    redis-cli lpush queue "$1 $2" 1> /dev/null 2>& 1 ||
    redis-cli rpush queue "$1 $2" 1> /dev/null 2>& 1