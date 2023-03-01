#!/bin/bash
# adds image to redis queue
main(){
    # if input is already queued, ignore it. 
    [[ ! -z $(redis-cli lrange queue 0 -1 | grep ${1}; exit 0) ]] && 
        /docker/log.sh WARN "This WSI is already queued! Ignoring: $1" && 
        return
        
    # if priority import, prepend, else, append
    /docker/log.sh INFO "Added to Queue: $1"
    [[ "${1##*/}" =~ "PRIORITY_" ]] &&
        redis-cli lpush queue "$1 $2" 1> /dev/null 2>& 1 ||
        redis-cli rpush queue "$1 $2" 1> /dev/null 2>& 1
}
main $@
