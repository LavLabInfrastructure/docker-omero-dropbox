#!/bin/bash
#Called when WSI fails screen
#sends emails to specified addresses and moves tiff to FAIL_DIR
/docker/log.sh WARN "REPORTING"
###FUNCTIONS
# sends email to defined addresses
sendEmails() {
    local IFS=';' read ADDR <<< ${ADMIN_EMAILS:-histoqcllabtestemailservice@proton.me}
    for i in "${ADDR[@]}"; do
        echo "Subject: Slide ${1##*/} has failed
            Slide ${1##*/} has failed the screen. It is located at $FAIL_DIR/${1##*/}. Please rescan or try importing again." | \
                sendmail $i 
    done
}

###MAIN
# if FAIL_DIR has not been bound, make a directory in IN_DIR
[[ ! -d $FAIL_DIR ]] && FAIL_DIR="/out/failed"
mkdir -p $FAIL_DIR

# move file to faildir
mv $1 $FAIL_DIR/${1##*/}

# send email to people
sendEmails $1