#!/bin/bash
# Handles HQC screening
/docker/log.sh INFO "HQCPIPE"

# if they forgot to define it, make it 20%
[[ -z $REQUIRED_PIXEL_PERCENT ]] && REQUIRED_PIXEL_PERCENT=20

# initial screen. Requires a valid pixel percentage 
[[ $REQUIRED_PIXEL_PERCENT -gt 0 ]] && [[ $REQUIRED_PIXEL_PERCENT -lt 101 ]] && \
    python -m histoqc --force -o /tmp/$2/screen/ $1 || /docker/log.sh ERROR "HistoQC failed. Check that REQUIRED_PIXEL_PERCENTAGE is within 100 and that your WSI is HQC compatible"

# determine if it passes (just using remaining tissue percentage
echo ${1##*/} /tmp/$2/screen/results.tsv
screenScore=$(/docker/getHQCStat.sh ${1##*/} "remaining_tissue_percent" /tmp/$2/screen/results.tsv)
screenScoreInteger=$( awk -v v=$screenScore 'BEGIN{ printf("%.0f\n", v*100)}')
/docker/log.sh INFO "$1 scored: $screenScoreInteger% in the hqc screen. It needs $REQUIRED_PIXEL_PERCENT% to pass"

#if results aren't within spec run report script and exit1, or exit0 and continue processImage 
[[ $screenScoreInteger -lt $REQUIRED_PIXEL_PERCENT ]] && \
    /docker/reportWSI.sh $1 && exit 1 || \
    exit 0