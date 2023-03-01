#/bin/bash 
# Listens to random port for new images to process
# propegate(){
#     /docker/log.sh INFO "QUITTING QUEUE"
#     jobs -p | while read pid
#     do
#         kill $pid
#     done
#     wait
# }

# start
[[ -z $MAX_JOBS ]] && echo "MISSING MAX_JOBS, SOMETHING WENT WRONG" && exit 1

# trap propegate SIGINT SIGTERM
while true
do  
    # if we have reached thread count, sleep
    jobCount=$(redis-cli llen running 2> /dev/null)
    [[ $jobCount -ge $MAX_JOBS ]] && sleep 30 && continue
    
    args=$(redis-cli blpop queue 0 | tail -n1 2> /dev/null)
    [[ -z $args ]] && /docker/log.sh WARN "Redis failed! Likely means the server is trying to shutdown, continuing" && exit 1
    IFS=' ' read a b <<< $args
    
    # if image is already running, wait for it to finish
    [[ ! -z $(redis-cli lrange running 0 -1 | grep ${a##*/}; exit 0) ]] && 
        /docker/log.sh WARN "Image with same name is already running! Sent $a to the back of the queue." && 
        redis-cli rpush queue "$a $b" 1> /dev/null 2>& 1 &&
        sleep 5 &&
        continue

    # # start a job
    job=$(redis-cli rpush running {"name":$a} 2> /dev/null)
    /docker/processImage.sh "$a" "$b" "$job" &
done
