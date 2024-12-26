#!/bin/bash

# Source setup.conf
source /opt/network_monitor/setup.conf

# Initialize variables
interface=""
target_ip=${REMOTE_DB_IP:-""}
bandwidth=""
port=5001

# Parse command-line options
while getopts "i:t:b:p:" opt; do
  case $opt in
    i) interface="$OPTARG" ;;
    t) target_ip="$OPTARG" ;;
    b) bandwidth="$OPTARG" ;;  # Accept bandwidth parameter here
    p) port="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
    :) echo "Option -$OPTARG requires an argument." >&2; exit 1 ;;
  esac
done

# Set default values if not provided
port=${port:-5001}
bandwidth=${bandwidth:-"1M"}  # Default bandwidth if not specified

# Run iperf3 client with specified or default bandwidth
iperf3 -c "$target_ip" -p "$port" ${bandwidth:+-b "$bandwidth"} -t 10 -J | while read -r line; do
    timestamp=$(date +"%Y-%m-%d %H:%M:%S.%3N")
    if [[ $line =~ \"bits_per_second\":([0-9.]+) ]]; then
        bitrate="${BASH_REMATCH[1]}"
        mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "INSERT INTO iperf_results (timestamp, bitrate) VALUES ('$timestamp', $bitrate);"
    fi
done
