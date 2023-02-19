#!/bin/bash
# watches a directory from /in for files added while server is up and uses that as context for histoqc processing
# ex. watchDir brain ; will watch /in/brain for files then pass "brain" to processImage for the correct pipeline 

# start watch
/docker/log.sh INFO "WATCHING /in/$1"
inotifywait -mr /in/$1 -e close_write |
	while read dir action file; do
		# if file extension is good, add it to queue
		if [[ $file =~ $WSI_EXTENSIONS ]]; then 
			/docker/queueImage.sh ${dir}${file} $1
		else
			/docker/log.sh WARN "$dir$file was ignored by watchFS"
		fi
	done