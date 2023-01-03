#!/bin/bash
#uses awk to grab a specific datapoint from tsv file
#ie: getHQCStat.sh 185_S20.tif pixels_to_use /tmp/pipe/results.tsv
##FUNCTIONS

#does the main work of extracting desire value
getValue() {
    awk 'BEGIN {
            FS="\t"
        } NR==6 {
            for ( i = 1; i <= NF; i++ ) {
                ix[$i] = i
            } 
        } NR > 6 {
            if ($1 == key) {
                print $ix[value]
            } 
        }' key=$1 value=$2 $3 
}

##MAIN
/docker/log.sh INFO "Getting $2 value from ${3%##/}"
# print use template if no args supplied
[[ -z $* ]] && /docker/log.sh ERROR "getHQCStat was called without args. follow this format" "getHQCStat.sh {filename} {hqc value name} {hqc results.tsv file}" && \
    exit 1

# if it is not a supported WSI format, complain
[[ $1 =~ !(.*\.tif$|.*\.tiff$|.*\.svs$|.*\.jpg$|.*\.vsi$) ]] && \
    /docker/log.sh ERROR "getHQCStat was expecting to know which slide you wanted data from" && \
    exit 1 

# if they did not ask for a key, complain
[[ -z $2 ]] && /docker/log.sh ERROR "get HQCStat was expecting a key to find a value" && \
    exit 1

# if you gave a non tsv file or the file doesn't exist, complain
([[ ! -f $3 ]] || [[ $3 != *.tsv ]]) && /docker/log.sh ERROR "getHQCStat was expecting a 'results.tsv' file, something went wrong" && \
    exit 1

# well we did what we could
stat=$(getValue $1 $2 $3)

# if we still get nothing, complain
([[ $stat == "" ]] && \
    /docker/log.sh ERROR "getHQCVal had valid syntax, but could not find what you were looking for." \
    "Compare your requested value, the slide name, and the contents of your hqc file" && \
    exit 1)

# Good Job!
echo $stat