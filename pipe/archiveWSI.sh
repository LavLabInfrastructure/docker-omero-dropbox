#!/bin/bash
#zip original files and send to dropbox or something
##FUNCTIONS

# SCP or something? idk some network transfer
transferArchive() {
    /docker/log.sh ERROR "network archiving is not implemented loser" && \
    exit 1
}

# tries to guess when you're done importing files, then zips it up
tarballArchive() {
    /docker/log.sh INFO "Tarballing $2:${1%##/}"
    # define tar file for easy reading
    local tarFile=$ARCHIVE_DIR/$2/${3##*/}.tar
     [[ ! -d $ARCHIVE_DIR/$2 ]] && mkdir -p $ARCHIVE_DIR/$2

    # if an archive is started, append to it
    [[ -f $tarFile ]] && tar -rf $tarFile $1|| \
    # else create the archive
    tar -cf $tarFile $1

    # if dataset directory is empty, gzip the archive and delete the directory
    [[ -z "$(ls -A $3)" ]] && rmdir $3 && 7z a $tarFile.gz $tarFile && rm $tarFile
}

# just makes a zip, and adds to it
zipArchive() {
    # if a zip already exists, just update it, else create a zip
    ([[ -e $ARCHIVE_DIR/$2 ]] && zip -fug $ARCHIVE_DIR/$2 $1 && /docker/log.sh INFO "ARCHIVE of $1 SUCCESSFUL") || \
        (zip -g $ARCHIVE_DIR/$2 $1 && /docker/log.sh INFO "ARCHIVE OF $1 SUCCESSFUL") || \
        (/docker/log.sh ERROR "ARCHIVE OF $1 FAILED" && exit 1)
}

##MAIN
/docker/log.sh INFO "ARCHIVE"
# define archive if it hasn't been
[[ -z $ARCHIVE_DIR ]] && ARCHIVE_DIR="/out/archive" && /docker/log.sh \
    WARN "ARCHIVE_DIR is not set, Using /out/archive"

# if ARCHIVE_ADDRESS is defined let them know it's not a feature
# if tarball, settle in. it'll take a while
# else zip 
([[ $ARCHIVE_ADDRESS ]] && transferArchive) ||
([[ $TARBALL ]] && tarballArchive $1 $2 $3) ||
zipArchive $1 $2

# Good Job!
exit 0
