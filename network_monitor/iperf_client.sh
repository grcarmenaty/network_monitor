#!/bin/bash

# Source setup.conf
source /opt/network_monitor/setup.conf

# Initialize variables
interface=""
target_ip=""
bandwidth=""
port=""

# Parse command-line options
while getopts "i:t:b:p:" opt; do
  case $opt in
    i) interface="$OPTARG" ;;
    t) target_ip="$OPTARG" ;;
    b) bandwidth="$OPTARG" ;;
    p) port="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
    :) echo "Option -$OPTARG requires an argument." >&2; exit 1 ;;
  esac
done

# Check if required parameters are provided
if [ -z "$interface" ] || [ -z "$target_ip" ] || [ -z "$port" ]; then
  echo "Error: Missing required parameters. Usage: $0 -i <interface> -t <target_ip> -p <port> [-b <bandwidth>]"
  exit 1
fi

# Get the local IP address
local_ip=$(ip -4 addr show dev "$interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
if [ -z "$local_ip" ]; then
  echo "Error: Could not retrieve IP address for interface $interface"
  exit 1
fi

echo "Using interface: $interface"
echo "Local IP address: $local_ip"
echo "Target IP address: $target_ip"
echo "Bandwidth: ${bandwidth:-not specified}"
echo "Port: $port"

# Record start time
start_time=$(date +%s.%N)

# Run iperf3 client
iperf3 -c "$target_ip" -u -R -p "$port" ${bandwidth:+-b "$bandwidth"} -t 0 -f m | while IFS= read -r line; do
    # Parse the iperf3 output line
    if [[ $line =~ \[.*\][[:space:]]+([0-9.]+)-([0-9.]+)[[:space:]]+sec[[:space:]]+[0-9.]+[[:space:]]MBytes[[:space:]]+([0-9.]+)[[:space:]]Mbits/sec[[:space:]]+([0-9.]+)[[:space:]]ms[[:space:]]+([0-9]+)/([0-9]+)[[:space:]]\(([0-9.]+)%\) ]]; then
        elapsed_time="${BASH_REMATCH[2]}"
        bitrate="${BASH_REMATCH[3]}"
        jitter="${BASH_REMATCH[4]}"
        lost_percentage="${BASH_REMATCH[7]}"
        
        # Calculate timestamp
        timestamp=$(date -d "@$(echo "$start_time + $elapsed_time" | bc)" +"%Y-%m-%d %H:%M:%S.%3N")
        
        # Insert data into the database
        mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "INSERT INTO iperf_results (timestamp, bitrate, jitter, lost_percentage) VALUES ('$timestamp', $bitrate, $jitter, $lost_percentage);" 2>/dev/null
    fi
done
