#!/bin/bash
#logs messages to appropriate file
##FUNCTIONS
# prints instructions
printHelp() {
    echo "Enter the message type, then the rest of the parameters will be logged"
    echo 'ie: ./log.sh WARN "uh oh error happened" $errormessage'
    echo "acceptable message types: INFO WARN ERROR"
    exit 1
}

# prints to log only
logMsg() {
    msgToLog $@ >> $LOG_DIR/pipeline.log
    exit 0
}

# prints to stdout and log
printMsg() {
    msgToLog $@ | tee -a $LOG_DIR/pipeline.log
    exit 0

}

# prints to stderr and log
printErr() {
    msgToLog $@ | tee -a $LOG_DIR/pipeline.log >&2
    exit 0
}

# adds message boilerplate
msgToLog() {
    echo "$(date +"%Y-%m-%d %T") - $1 - ${@:2}"
}

##MAIN
# if it's an invalid message type print help
[[ ! ($1 =~ ^INFO$|^WARN$|^ERROR$|^NONE$) ]] && printHelp

# if they only gave a message type, demand an actual message
[[ $# -le 1 ]] && echo "you only told us what kind of log, not what to log" && printHelp

# if they chose none, do not send anything to stderr/stdout 
[[ $LOG_LEVEL == NONE ]] && logMsg $@ 
# otherwise errors use the printErr function 
[[ $1 == ERROR ]] && printErr $@ 
# if INFO is selected, all non-errors get printed to STDOUT 
[[ $LOG_LEVEL == INFO ]] && printMsg $@
#if WARN is selected, INFO level logs don't use printMsg 
([[ $LOG_LEVEL == WARN ]] && [[ $1 == WARN ]] && printMsg $@) \
    || logMsg $@