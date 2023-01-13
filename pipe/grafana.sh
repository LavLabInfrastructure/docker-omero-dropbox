#!/bin/bash
# Formats current pipeline status to JSON 
# JSON written for use in Grafana w/ JSON API Data Source by Marcus Olsson

static=$(cat $GRAFANA_STATIC)

IFS= read processing << EOF
$( (cat /tmp/PROCESSING/*/json | jq -cs '') 2> /dev/null)
EOF
[[ -z $processing ]] && processing="[]"

IFS= read queue << EOF
$(jq --slurp -Rcs 'split("\n")|map(split(" ")|.[0]?)' $QUEUE_FILE 2> /dev/null)
EOF
[[ -z $queue ]] && queue="[]"
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
