#/bin/bash 
# Listens to random port for new images to process
propegate(){
    /docker/log.sh INFO "QUITTING QUEUE"
    jobs -p | while read pid
    do
        /docker/log.sh INFO $pid
        kill $pid
    done
    wait
}

# start
[[ -z $OUT_PORT ]] && echo "MISSING OUT_PORT, SOMETHING WENT WRONG" && exit 1
[[ -z $REQ_PORT ]] && echo "MISSING REQ_PORT, SOMETHING WENT WRONG" && exit 1
[[ -z $MAX_THREADS ]] && echo "MISSING MAX_THREADS, SOMETHING WENT WRONG" && exit 1

trap propegate SIGINT SIGTERM
while true
do  
    
    # While no output, request output (no output likely means server is not up yet) 
    while ! { read a b < /dev/tcp/localhost/$OUT_PORT; } 2>/dev/null
    do
        echo "please?" > /dev/tcp/localhost/$REQ_PORT
        sleep 1 
    done
    # "wait" means there are no items to process, sleep then try again
    [[ $a == "wait" ]] && echo "waiting..." && sleep 5 && continue

    # start a thread
    /docker/processImage.sh "$a" "$b" &

    # if we have reached thread count do not ask for more until one has finished
    background=( $(jobs -p) )
    [[ ${#background[@]} -ge $MAX_THREADS ]] && wait -n 
done
