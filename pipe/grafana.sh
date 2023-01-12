#!/bin/bash
# Formats current pipeline status to JSON 
# JSON written for use in Grafana w/ JSON API Data Source by Marcus Olsson

# conversion type
filetype="ome.tiff"
[[ ! -z $CONVERT_TO_ZARR ]] && filetype="ome.zarr"

# gather data on processes 
processing="[ "
for dir in $(ls /tmp/PROCESSING)
do
    stdout=/tmp/PROCESSING/$dir/out
    # get latest line (progress bar does not print new line
    #       so this is some trickery to get a line instantly
    line=$( (timeout 1 cat $stdout; exit 0) | tail -1 )

    # progress bars start like '[0/0]', text means an unimportant line
    if [[ "$line" =~ ^[A-Za-z]+  ]] || [[ -z $line ]]; then
        # default
        plane="[0/0]"
        percent="0%"
        timer="0:00:00"
        timeLeft="?"
    else
        # extract data
        plane=$(echo $line | awk '{print $1}')
        percent=$(echo $line | awk '{print $2}')
        timer=$(echo $line | awk -F "[ ]*[(/)]+[ ]*" '{print $4}')
        timeLeft=$(echo $line | awk -F "[ ]*[(/)]+[ ]*" '{print $5}')
    fi

    json=$( jq -n \
        --arg name "${dir%.d}" \
        --arg current_plane "${plane}" \
        --arg percent_done "$percent" \
        --arg time_elapsed "$timer" \
        --arg estimated_time_remaining "$timeLeft" \
        '$ARGS.named')
        
    processing="${processing}${json},"
done
processing="${processing::-1} ]"

# get queue
queue=$(jq -Rs 'split("\n")|map(split(" ")|{name:.[0]}?)' <$QUEUE_FILE)

# form complete json data
JSON_STRING=$(jq -n \
                  --arg pipeline_maximum_threads "$MAX_THREADS" \
                  --arg pipeline_converted_filetype "$filetype" \
                  --arg pipeline_zarr_args "$BF2RAW_ARGS" \
                  --arg pipeline_ometiff_args "$RAW2TIFF_ARGS" \
                  --argjson pipeline_running_threads "$processing" \
                  --argjson pipeline_queued_images "$queue" \
                   '$ARGS.named')

# print http response
echo "HTTP/1.1 200 OK
Content-Type: text/json 

$JSON_STRING"