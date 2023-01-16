#!/bin/bash
#Gets called once per image. Use this script to run any programs you'd like on your image prior to import
set -e
cleanup(){
    if [[ -d $workdir ]];then
        /docker/log.sh INFO "$filename failed processing! Returning to original directory..."
        mv $workdir/$filename $parentPath/$filename
        rm -rf $workdir/*
        rmdir $workdir
    fi
}

parseStdout(){
    local stdout=$1
    local jsonPath=$workdir/json

    jq -cn \
        --arg name "$filename" \
        --arg current_plane "[0/0]" \
        --arg percent_done "0%" \
        --arg time_elapsed "0:00:00" \
        --arg estimated_time_remaining "?" \
        '$ARGS.named' > $jsonPath
    while [[ -d $workdir ]] 
    do
        sleep 2
        # get latest line (progress bar does not print new line
        #       so this is some trickery to get a line instantly)
        [[ ! -p $stdout ]] && exit
        line=$( (timeout 3 cat $stdout; exit 0) | tail -1 ) 2> /dev/null
        # alphabet means an unimportant line
        if [[ ! "$line" =~ ^[A-Za-z]+  ]] && [[ ! -z $line ]]; then
            # scrape line
            plane=$(echo $line | awk '{print $1}')
            percent=$(echo $line | awk '{print $2}')
            timer=$(echo $line | awk -F "[ ]*[(/)]+[ ]*" '{print $4}')
            timeLeft=$(echo $line | awk -F "[ ]*[(/)]+[ ]*" '{print $5}')
            
            # # get current values
            # jsonPlane="jq .current_plane $jsonPath"
            # jsonPercent="jq .percent_done $jsonPath"
            # jsonTimer="jq .time_elapsed $jsonPath"
            # jsonTimeLeft="jq .estimated_time_remaining $jsonPath"

            # for var in "jsonPlane" "jsonPercent" "jsonTimer" "jsonTimeLeft"
            # do
            #     [[ ! -f $jsonPath ]] && echo "stopping parser HERE" && exit
            #     ${!var} | read $var
            # done

            [[ ! -f $jsonPath ]] && exit
            jq -cn \
            --arg name "$filename" \
            --arg current_plane "${plane}" \
            --arg percent_done "$percent" \
            --arg time_elapsed "$timer" \
            --arg estimated_time_remaining "$timeLeft" \
            '$ARGS.named' > $jsonPath
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

    workdir=/tmp/PROCESSING/$filename.d
    local currentImg=$workdir/$filename

    #mv to tmp directory (to avoid multiple calls on same file) 
    [[ -d $workdir ]] && /docker/log.sh ERROR "Work directory for $filename is already occupied!" && exit 1
    /docker/log.sh INFO "PROCESSING $filename"
    trap cleanup EXIT SIGINT SIGTERM
    mkdir -p $workdir
    mv $1 $workdir/$filename
    
    # stdout scraper
    local stdout=$workdir/out
    mkfifo $stdout
    parseStdout $stdout &

    #convert to zarr
    if [[ $CONVERT_TO_ZARR ]]; then
        /docker/log.sh INFO "converting to zarr"
        /docker/bin/bioformats2raw -p --max_workers=$threads "$currentImg" "/out/$2/$dataset/${filename%.*}/" $BF2RAW_ARGS >$stdout 2>&1 
        /docker/log.sh INFO "converted to zarr"
    fi 

    #convert to ome.tiff
    if [[ $CONVERT_TO_TIFF ]]; then 
        /docker/log.sh INFO "converting to ome.tiff"
        mkdir -p "/out/$2/$dataset" 
        /docker/bin/bioformats2raw -p --max_workers=$threads "$currentImg" "$workdir/zarr" $BF2RAW_ARGS >$stdout 2>&1 || exit
        /docker/log.sh INFO "converted to zarr"

        /docker/bin/raw2ometiff -p --max_workers=$threads "$workdir/zarr" "/out/$2/$dataset/${filename%.*}.ome.tiff" $RAW2TIFF_ARGS >$stdout 2>&1 
        /docker/log.sh INFO "converted to ome.tiff" 
    fi
    #zip and archive (medusa?siren? wherever rsync goes now.)
    # [[ $ARCHIVE_ORIGINAL ]] && /docker/archiveWSI.sh $currentImg ${2%/} $parentPath

    #these files are huge, cannot afford to keep them kicking around
    /docker/log.sh INFO "cleaning workdir"
    ls -la $workdir > /dev/null # i cannot comprehend why but this is REQUIRED to delete properly
    rm -rf $workdir/* 
    rmdir $workdir
}

[[ -z $1 ]] && /docker/log.sh ERROR "No file provided" && exit 1
main $@
exit 0