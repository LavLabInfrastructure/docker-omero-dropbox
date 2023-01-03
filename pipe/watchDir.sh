#!/bin/bash
# watches a directory from /in for files added while server is up and uses that as context for histoqc processing
# ex. watchDir brain ; will watch /in/brain for files then pass "brain" to processImage for the correct pipeline 
/docker/log.sh INFO "WATCHING DIRECTORIES"
# queue existing files that will be missed by watchfs 
regex=$(echo '.*\.tif$|.*\.tiff$|.*\.svs$|.*\.jpg$|.*\.vsi$' | sed 's/|/\\|/g')
find /in/$1 -iregex $regex \
	-exec /bin/echo {} "$1" > /dev/tcp/localhost/$IN_PORT \;

# start watch
inotifywait -mr /in/$1 -e close_write |
	while read dir action file; do
		# if file extension is good, add it to queue
		if [[ $file =~ $WSI_EXTENSIONS ]]; then 
			# /docker/log.sh INFO "file: $file in: $dir was: $action"
			# send to IN_PORT
			echo "${dir}${file}" "$1" >/dev/tcp/localhost/$IN_PORT
		else
			/docker/log.sh WARN "$dir$file was ignored by watchFS"
		fi
	done