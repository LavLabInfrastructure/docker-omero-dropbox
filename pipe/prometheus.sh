#!/bin/bash
# exports a couple metrics for prometheus alerts

echo "pipeline_queue_count $(wc -l <$QUEUE_FILE)"
echo "pipeline_processing_count $(ls /tmp/PROCESSING | wc -l)"
echo "pipeline_max_threads $(echo $MAX_THREADS)" 