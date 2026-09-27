#!/bin/bash
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

# Probe the daemon itself rather than `service docker status`: the SysV script
# sets ulimits the container rejects, so it is unreliable here.
if docker info >/dev/null 2>&1; then
    echo "$(date) | Service is running.... exiting"
    exit 0
fi

echo "$(date) | Service is not running...Starting service"

ulimit -n 1048576 2>/dev/null || true
ulimit -u unlimited 2>/dev/null || true

# Detach from cron so the daemon is not reaped when this job exits.
setsid dockerd >>/var/log/dockerd.log 2>&1 < /dev/null &

for i in $(seq 1 30); do
    if docker info >/dev/null 2>&1; then
        echo "$(date) | Service started after ${i}s"
        exit 0
    fi
    sleep 1
done

echo "$(date) | Service failed to start; see /var/log/dockerd.log" >&2
exit 1
