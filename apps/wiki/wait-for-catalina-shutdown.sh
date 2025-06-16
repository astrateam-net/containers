#!/bin/bash

##############################################################################
#
# This script will wait for catalina.sh to finish stopping confluence before continuing.
# This is primarily intended to be called by the entrypoint script, after the main confluence process 
# has terminated.
#
################################################################################

### Get pid of catalina.sh
pid=$(ps -ef | grep -w catalina.sh | grep -v grep | awk '{print $2}')

# Exit if $pid is empty
if [ -z "$pid" ]; then
    echo "No process found for catalina.sh. Exiting." >> ${CONFLUENCE_HOME}/logs/shutdown.log
    exit 0
else
    echo "Process ID of catalina.sh: $pid" >> ${CONFLUENCE_HOME}/logs/shutdown.log
fi


### Wait for process with $pid to finish

timeout=120
start_time=$(date +%s)

while kill -0 $pid 2> /dev/null; do
    sleep 1
    # Check if timeout has been reached
    current_time=$(date +%s)
    elapsed_time=$((current_time - start_time))
    if [ $elapsed_time -ge $timeout ]; then
        echo "Timeout reached after $timeout seconds." >> ${CONFLUENCE_HOME}/logs/shutdown.log
        break
    fi
    echo "Sleeping, waiting for process $pid to finish..." >> ${CONFLUENCE_HOME}/logs/shutdown.log
done

echo "----- Wait for shutdown has finished -----" >> ${CONFLUENCE_HOME}/logs/shutdown.log

exit 0
