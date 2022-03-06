#!/bin/bash
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
STATUS="$(service docker status |awk '{print $4}')"
if [ "${STATUS}" = "not" ]; then
    echo `date` "| Service is not running...Starting service"
    service docker start
else 
    echo `date` "| Service is running.... exiting "  
    exit 1  
fi
