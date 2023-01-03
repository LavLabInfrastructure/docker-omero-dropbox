#!/docker/dumb-init /bin/bash
# starts watching each directory of /in/ 
set -e

##### TODO: #####
##### DONE #####
# scraper DONE
# multithreading DONE
# continue imports DONE
# priorty imports DONE
# only care about important directories DONE
# email on failure DONE


# start microserver
# Writes data from IN_PORT to file and returns that info on OUT_PORT
# should allow multiple writers, a single process manager, multiple processes, and continuing after reboot
# this is awfully hacky but if it works whatever ig

# starts an input server
input(){
    # find open port in private range (49152-65535) 
    while
    local PORT=$(shuf -n 1 -i 49152-65535)
    netstat -atun | grep -q "$PORT"
    do 
        continue 
    done
    export IN_PORT=$PORT
    
    # start input port, print input to file
    nc -k -l $IN_PORT | while read a b
    do  
        # if input is queued, ignore it. 
        [[ ! -z $(grep \'$a\' $QUEUE_FILE) ]] && continue
        # if priority import, prepend, else, append
        [[ "${a##*/}" =~ "PRIORITY_" ]] &&
            echo -e "$a $b\n$(cat $QUEUE_FILE)" > $QUEUE_FILE ||
            echo "$a" "$b" >> $QUEUE_FILE 
        /docker/log.sh INFO "Added to Queue: $a"
    done &
}

# starts the output server
output(){
    # find 2 open ports in private range (49152-65535) 
    while
    local PORT=$(shuf -n 1 -i 49152-65535)
    netstat -atun | grep -q "$PORT"
    do 
        continue 
    done
    export OUT_PORT=$PORT

    while
    PORT=$(shuf -n 1 -i 49152-65535)
    netstat -atun | grep -q "$PORT" && [[ $PORT != $OUT_PORT ]]
    do 
        continue 
    done
    export REQ_PORT=$PORT
    
    # listen to request port
    nc -k -l $REQ_PORT | while read a
    do
        local line="wait"
        if [[ $(wc -l $QUEUE_FILE) != "0 $QUEUE_FILE" ]]; then
            line=$(head -n 1 $QUEUE_FILE) 
            sed -i '1d' $QUEUE_FILE
        fi
        echo $line | nc -l $OUT_PORT
        
        # on request, send item through OUT_PORT then remove it from queue if we have one otherwise sent 'wait' # | nc -l $OUT_PORT
        # read -r line < $QUEUE_FILE
        # [[ -z $line ]] && continue
        # echo $line > /dev/tcp/localhost/$OUT_PORT
        # tail -n +2 "$QUEUE_FILE" > "$QUEUE_FILE.tmp" && \
        #     mv "$QUEUE_FILE.tmp" "$QUEUE_FILE"
    done & 
}

# source and export environment
set -a
. /docker/.env
set +a

# create queue file
[[ -z $QUEUE_FILE ]] && export QUEUE_FILE="/in/.queue" 
[[ ! -f $QUEUE_FILE ]] && touch $QUEUE_FILE


# if logdir is not defined, define it
[[ -z $LOG_DIR ]] && export LOG_DIR=/out/log 
mkdir -p $LOG_DIR 

[[ -z $WSI_EXTENSIONS ]] && export WSI_EXTENSIONS='.*\.tif$|.*\.tiff$|.*\.svs$|.*\.jpg$|.*\.vsi$'
[[ -z $MAX_THREADS ]] && export MAX_THREADS=2

[[ -z $CONVERT_TO_TIFF ]] && [[ -z $CONVERT_TO_ZARR ]] &&
    CONVERT_TO_TIFF=true

# tmp folder 
mkdir -p /tmp/PROCESSING

# start microserver
input 
output 

# start processor
/docker/processQueue.sh &

# watch each subdirectory of /in
cd /in
for d in */; do
    /docker/watchDir.sh ${d%/} &
done

# grafana datasource
[[ $ENABLE_GRAFANA ]] && socat -U TCP-LISTEN:13000,fork EXEC:'/docker/grafana.sh',stderr,pty,echo=0 &

# prometheus exporter
[[ $ENABLE_PROMETHEUS ]] && /docker/prometheus-bash-exporter &

# Good Job!
/docker/log.sh INFO "Finished establishing all watches"
wait
