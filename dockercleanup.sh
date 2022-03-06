#!/bin/sh
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
output=$(df -H | grep -vE '^Filesystem|tmpfs|cdrom' | awk '{ print $5 " " $6 }' | grep /var/lib/docker)
usep=$(echo $output | awk '{ print $1}' | cut -d'%' -f1  )
partition=$(echo $output | awk '{ print $2 }' )
runningjob=$(df -H | grep /var/lib/docker/overlay)
if [ $usep -ge 90 ] && [ -z "$runningjob" ]; then
   echo `date` >> /var/log/dockercleanup.log 2>&1
   echo `date` "Running out of space on partition \"$partition ($usep%)\" " >> /var/log/dockercleanup.log 2>&1
   echo `date` "Deleting images" >> /var/log/dockercleanup.log 2>&1
   docker rmi -f $(docker images -aq) >> /var/log/dockercleanup.log 2>&1
   echo `date` "Deleting containers" >> /var/log/dockercleanup.log 2>&1
   docker container rm $(docker container ls -aq) >> /var/log/dockercleanup.log 2>&1
else
   echo `date` "| $partition below threshold, current usage is $usep%" >> /var/log/dockercleanup.log 2>&1
   exit 1
fi