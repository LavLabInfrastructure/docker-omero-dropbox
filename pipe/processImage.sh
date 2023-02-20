#!/bin/bash
#Gets called once per image. Use this script to run any programs you'd like on your image prior to import
set -e
cleanup(){
    /docker/log.sh INFO "cleaning workdir"
    rm -f $currentImg
    rm -rf $workdir

    # removing a certain index is a little tricky in redis
    redis-cli lrem running -1 "$(redis-cli LINDEX running $job 2> /dev/null)" 1> /dev/null 2>& 1
    [[ -z $fin ]] && 
        /docker/log.sh ERROR "$filename failed processing! Leaving file at $currentImg This image will be attempted again at startup."
    exit
}

parseStdout(){
    local stdout=$1

    # set default json
    local json=$(jq -cn \
        --arg name "$filename" \
        --arg current_plane "[0/0]" \
        --arg percent_done "0%" \
        --arg time_elapsed "0:00:00" \
        --arg estimated_time_remaining "?" \
        '$ARGS.named' )
    redis-cli lset running "$job" "$json" 1> /dev/null 2>& 1

    while [[ -d $workdir ]] 
    do
        sleep 2
        [[ ! -p $stdout ]] && exit
        # get latest line (progress bar does not print new line
        #       so this is some trickery to get a line instantly)
        line=$( (timeout 3 cat $stdout; exit 0) | tail -1 ) 2> /dev/null
        # alphabet means an unimportant line
        if [[ ! "$line" =~ ^[A-Za-z]+  ]] && [[ ! -z $line ]]; then
            # scrape line
            plane=$(echo $line | awk '{print $1}')
            percent=$(echo $line | awk '{print $2}')
            timer=$(echo $line | awk -F "[ ]*[(/)]+[ ]*" '{print $4}')
            timeLeft=$(echo $line | awk -F "[ ]*[(/)]+[ ]*" '{print $5}')

            json=$(jq -cn \
            --arg name "$filename" \
            --arg current_plane "${plane}" \
            --arg percent_done "$percent" \
            --arg time_elapsed "$timer" \
            --arg estimated_time_remaining "$timeLeft" \
            '$ARGS.named') 
            redis-cli lset running "$job" "$json" 1> /dev/null 2>& 1
        fi
    done
}

main(){    
    #gather title info
    filename=${1##*/}
    parentPath=${1%/*}
    local datasetPath=$(echo $parentPath | sed "s/\/in\/$2\///g")
    local dataset=${datasetPath%%/*}
    local threads=${BASE_THREADS:-1}

    [[ -z $dataset ]] && dataset=orphaned

    # if priority import rename and add threads
    [[ $filename =~ "PRIORITY_" ]] && 
        filename=${filename#PRIORITY_} &&
        threads=${PRIORITY_THREADS:-2} 

    workdir=/tmp/$filename.d
    currentImg=/in/.PROCESSING/$2/$dataset/$filename


    # start processing
    /docker/log.sh INFO "PROCESSING $filename"
    trap cleanup EXIT SIGINT SIGTERM

    #mv to dif directory (to avoid multiple calls on same file) 
    mkdir -p /in/.PROCESSING/$2/$dataset $workdir
    [[ $1 != $currentImg ]] && mv -f $1 $currentImg
    
    # grafana stdout scraper
    local stdout=$workdir/out
    mkfifo $stdout
    parseStdout $stdout &

    #convert to zarr
    if [[ $CONVERT_TO_ZARR == true ]]; then
        output=/out/$2/$dataset/${filename%.*}/
        /docker/log.sh INFO "$filename is converting to zarr"
        /docker/bin/bioformats2raw -p --max_workers=$threads "$currentImg" "$output" $BF2RAW_ARGS >$stdout 2>&1 
        /docker/log.sh INFO "$filename was converted to zarr"
    fi 

    #convert to ome.tiff
    if [[ $CONVERT_TO_TIFF == true ]]; then 
        output=/out/$2/$dataset/${filename%.*}.ome.tiff
        /docker/log.sh INFO "$filename is converting to ome.tiff"
        mkdir -p "/out/$2/$dataset" 
        /docker/bin/bioformats2raw -p --max_workers=$threads "$currentImg" "$workdir/zarr" $BF2RAW_ARGS >$stdout 2>&1 || exit
        /docker/log.sh INFO "$filename was converted to zarr"

        /docker/bin/raw2ometiff -p --max_workers=$threads "$workdir/zarr" "$output" $RAW2TIFF_ARGS >$stdout 2>&1 || exit
        /docker/log.sh INFO "$filename was converted to ome.tiff" 
        # # if it was previously an ome tiff, keep metadata
        # echo $currentImg
        # if [[ $currentImg =~ \.ome\.tiff$ ]]; then
        #     echo "here"
        #     /docker/tiffcomment $currentImg | /docker/tiffcomment -set -- $output
        # fi
    fi

    # finished succesfully!
    fin=true
    exit 0
}

[[ -z $1 ]] && /docker/log.sh ERROR "No file provided" && exit 1
job=$(($3-1))
main $1 $2
exit 0