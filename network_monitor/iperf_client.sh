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

# Run iperf3 client with improved parsing and unbuffered output
echo "🚀 Starting iperf3 client to collect bandwidth data..."
stdbuf -oL -eL iperf3 -c "$target_ip" -u -R -p "$port" ${bandwidth:+-b "$bandwidth"} -t 0 -f m -i 1 | while IFS= read -r line; do
    echo "DEBUG: $line"  # Debug output to see what we're receiving
    
    # Parse different iperf3 output formats
    # Format 1: [  5]   0.00-1.00   sec   129 KBytes  1.05 Mbits/sec  91
    if [[ $line =~ \[[[:space:]]*[0-9]+\][[:space:]]+([0-9.]+)-([0-9.]+)[[:space:]]+sec[[:space:]]+[0-9.]+[[:space:]]+[KMG]?Bytes[[:space:]]+([0-9.]+)[[:space:]]+[KMG]?bits/sec[[:space:]]+([0-9]+) ]]; then
        elapsed_time="${BASH_REMATCH[2]}"
        bitrate="${BASH_REMATCH[3]}"
        datagrams="${BASH_REMATCH[4]}"
        
        # Convert bitrate to Mbits/sec if needed
        if [[ $line =~ ([0-9.]+)[[:space:]]+Kbits/sec ]]; then
            bitrate=$(awk "BEGIN {printf \"%.3f\", ${BASH_REMATCH[1]} / 1000}")
        elif [[ $line =~ ([0-9.]+)[[:space:]]+Gbits/sec ]]; then
            bitrate=$(awk "BEGIN {printf \"%.3f\", ${BASH_REMATCH[1]} * 1000}")
        fi
        
        # Calculate accurate timestamp based on measurement time
        measurement_time=$(awk "BEGIN {printf \"%.3f\", $start_time + $elapsed_time}")
        timestamp=$(date -d "@$measurement_time" +"%Y-%m-%d %H:%M:%S.%3N")
        
        # Insert data into the database immediately (using 0 for jitter and lost_percentage as they're not in this format)
        echo "📊 Inserting REAL-TIME: timestamp=$timestamp, bitrate=$bitrate"
        mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "INSERT INTO iperf_results (timestamp, bitrate, jitter, lost_percentage) VALUES ('$timestamp', $bitrate, 0, 0);" 2>/dev/null
        
    # Format 2: UDP format with jitter and loss
    elif [[ $line =~ \[[[:space:]]*[0-9]+\][[:space:]]+([0-9.]+)-([0-9.]+)[[:space:]]+sec[[:space:]]+[0-9.]+[[:space:]]+[KMG]?Bytes[[:space:]]+([0-9.]+)[[:space:]]+[KMG]?bits/sec[[:space:]]+([0-9.]+)[[:space:]]+ms[[:space:]]+([0-9]+)/([0-9]+)[[:space:]]\(([0-9.]+)%\) ]]; then
        elapsed_time="${BASH_REMATCH[2]}"
        bitrate="${BASH_REMATCH[3]}"
        jitter="${BASH_REMATCH[4]}"
        lost_percentage="${BASH_REMATCH[7]}"
        
        # Calculate accurate timestamp based on measurement time
        measurement_time=$(awk "BEGIN {printf \"%.3f\", $start_time + $elapsed_time}")
        timestamp=$(date -d "@$measurement_time" +"%Y-%m-%d %H:%M:%S.%3N")
        
        echo "📊 Inserting REAL-TIME: timestamp=$timestamp, bitrate=$bitrate, jitter=$jitter, loss=$lost_percentage%"
        mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "INSERT INTO iperf_results (timestamp, bitrate, jitter, lost_percentage) VALUES ('$timestamp', $bitrate, $jitter, $lost_percentage);" 2>/dev/null
    fi
done
