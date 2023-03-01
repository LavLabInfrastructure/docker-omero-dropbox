#!/docker/dumb-init /bin/bash
# starts watching each directory of /in/ 
set -e
# propegate(){
#     /docker/log.sh INFO "QUITTING ENTRYPOINT"
#     jobs -p | while read pid
#     do
#         kill $pid
#     done
#     wait
# }

# provides grafana configs and prepares grafana json datasource endpoint
initGrafana(){
    echo "starting grafana"
    # add configs to volume
    cp -r /configs/grafana/*/ /etc/grafana/provisioning  

    # conversion type
    filetype="ome.tiff"
    [[ ! -z $CONVERT_TO_ZARR ]] && filetype="ome.zarr"

    # form static json data
    export GRAFANA_STATIC=/tmp/static.json
    jq -rcn \
        --arg maximum_jobs "$MAX_JOBS" \
        --arg converted_filetype "$filetype" \
        --arg zarr_args "$BF2RAW_ARGS" \
        --arg ometiff_args "$RAW2TIFF_ARGS" \
        '$ARGS.named' > $GRAFANA_STATIC

    socat -U TCP-LISTEN:13000,fork EXEC:"/docker/grafana.sh",stderr,pty,echo=0 &
}

# START
echo "Starting..."

# trap propegate SIGINT SIGTERM EXIT
# start fresh redis instance
rm -rf /dump.rdb
redis-server > /dev/null &

# source and export environment
set -a
for file in /configs/*.env
do
    [[ $file == /configs/sample.env ]] && continue
    . $file
done
set +a

# define required variables
export LOG_DIR=/log 
export WSI_EXTENSIONS=${WSI_EXTENSIONS:-'.*\.tif$|.*\.tiff$|.*\.svs$|.*\.jpg$|.*\.vsi$'}
export MAX_JOBS=${MAX_JOBS:-2}
[[ -z $CONVERT_TO_TIFF ]] && [[ -z $CONVERT_TO_ZARR ]] && 
    export CONVERT_TO_TIFF=true

mkdir -p $LOG_DIR
mkdir -p /in/.PROCESSING
cd /in

# resume conversions
/docker/log.sh INFO "Searching processing directory for stopped conversions"
/docker/findImages.sh .PROCESSING/*

# watch each subdirectory of /in, besides the processing folder
for d in */; do
    /docker/findImages.sh ${d%/}
    /docker/watchDir.sh ${d%/} &
done
/docker/log.sh INFO "Finished establishing all watches"

# export grafana datasource and start exporter
ENABLE_GRAFANA=true
[[ $ENABLE_GRAFANA ]] && initGrafana
    
# start prometheus exporter (discovered by prometheus-docker-sd)
ENABLE_PROMETHEUS=true
[[ $ENABLE_PROMETHEUS ]] && \
    echo "starting prometheus" && /docker/prometheus-bash-exporter > /dev/null &

# start processor
/docker/processQueue.sh

