#!/usr/bin/env bash
set -e

echo "Data Folder and Docker Usage:"
sudo du -hxd1 /opt/streamlab/data /var/lib/docker | sort -h
echo

echo "Docker Disk Usage:"
docker system df -v
echo

echo "Running Container Writable Layer Sizes:"
docker ps --size
echo

echo "Docker JSON Log Sizes:"
sudo find /var/lib/docker/containers -name '*-json.log' -exec du -h {} + | sort -h
echo

echo "Streamlab App Data Usage:"
sudo du -sh /opt/streamlab/data/*

exit 0
