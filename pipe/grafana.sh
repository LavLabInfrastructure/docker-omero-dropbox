#!/bin/bash
# Formats current pipeline status to JSON 
static=$(cat $GRAFANA_STATIC)

json="$(redis-cli lrange running 0 -1 2> /dev/null)"
processing="[$(echo -n $json | tr ' ' ',')]"
[[ $processing =~ "null" ]] && processing="[]"

arr=()
while read line
do
    arr+=(${line%\ *})
done <<< "$(redis-cli lrange queue 0 -1)"
queue=$(jq -rcn '$ARGS.positional' --args -- "${arr[@]}")
# json="$(redis-cli lrange queue 0 -1 2> /dev/null)"
# echo $json
# queue="$(echo $json | jq -rcn '')"
# [[ $queue == "null" ]] && queue="[]"
# echo $processing
echo $queue
# form complete json data
JSON_STRING=$(jq -n \
                  --argjson pipeline_static_configs "$static" \
                  --argjson pipeline_running_threads "$processing" \
                  --argjson pipeline_queued_images "$queue" \
                   '$ARGS.named')

# print http response
echo "HTTP/1.1 200 OK
Content-Type: text/json 

$JSON_STRING"
