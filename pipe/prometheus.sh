#!/bin/bash
# exports a couple metrics for prometheus alerts

echo "pipeline_queue_count $(redis-cli llen queue 2> /dev/null))"
echo "pipeline_processing_count $(redis-cli llen running 2> /dev/null))"
echo "pipeline_max_jobs $(echo $MAX_JOBS)" 