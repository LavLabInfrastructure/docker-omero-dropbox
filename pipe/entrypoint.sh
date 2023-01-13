#!/docker/dumb-init /bin/bash
# starts watching each directory of /in/ 
set -e
propegate(){
    /docker/log.sh INFO "QUITTING ENTRYPOINT"
    jobs -p | while read pid
    do
        kill $pid
    done
    wait
}

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
    done & 
}

# provides grafana configs and prepares grafana json datasource endpoint
initGrafana(){
    echo "starting grafana"
    export GRAFANA_STATIC=/tmp/static.json
    # add configs to volume
    cp -r /configs/grafana/*/ /etc/grafana/provisioning  

    # conversion type
    filetype="ome.tiff"
    [[ ! -z $CONVERT_TO_ZARR ]] && filetype="ome.zarr"

    # get queue
    # queue=$(jq -Rs 'split("\n")|map(split(" ")|{name:.[0]}?)' <$QUEUE_FILE)

    # form static json data
    jq -n \
        --arg maximum_threads "$MAX_THREADS" \
        --arg converted_filetype "$filetype" \
        --arg zarr_args "$BF2RAW_ARGS" \
        --arg ometiff_args "$RAW2TIFF_ARGS" \
        '$ARGS.named' > $GRAFANA_STATIC

    socat -U TCP-LISTEN:13000,fork EXEC:'/docker/grafana.sh',stderr,pty,echo=0 &
}
trap propegate SIGINT SIGTERM
# source and export environment
set -a
echo "Starting..."
for file in /configs/*.env
do
    [[ $file == /configs/sample.env ]] && continue
    . $file
done
set +a

# create queue file
export QUEUE_FILE="/tmp/.queue" 
mkdir /tmp && touch $QUEUE_FILE


# if logdir is not defined, define it
[[ -z $LOG_DIR ]] && export LOG_DIR=/log 
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


# watch each subdirectory of /in
cd /in
for d in */; do
    /docker/watchDir.sh ${d%/} &
done
/docker/log.sh INFO "Finished establishing all watches"

# export grafana datasource and start exporter
ENABLE_GRAFANA=true
[[ $ENABLE_GRAFANA ]] && initGrafana
    
# start prometheus exporter (discovered by prometheus-docker-sd)
ENABLE_PROMETHEUS=true
[[ $ENABLE_PROMETHEUS ]] && \
    echo "starting prometheus" && /docker/prometheus-bash-exporter &

# start processor
exec /docker/processQueue.sh

