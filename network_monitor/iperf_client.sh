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
    b) bandwidth="$OPTARG" ;;  # Accept bandwidth parameter here
    p) port="$OPTARG" ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
    :) echo "Option -$OPTARG requires an argument." >&2; exit 1 ;;
  esac
done

# Check if interface is provided
if [ -z "$interface" ]; then
  echo "Error: Interface not specified. Use -i flag to specify the interface."
  exit 1
fi

# Check if target IP is provided
if [ -z "$target_ip" ]; then
  echo "Error: Target IP not specified. Use -t flag to specify the target IP."
  exit 1
fi

# Check if port is provided
if [ -z "$port" ]; then
  echo "Error: Port not specified. Use -p flag to specify the port."
  exit 1
fi

# Get the local IP address
local_ip=$(ip -4 addr show dev "$interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

# Check if local_ip was successfully retrieved
if [ -z "$local_ip" ]; then
  echo "Error: Could not retrieve IP address for interface $interface"
  exit 1
fi

echo "Using interface: $interface"
echo "Local IP address: $local_ip"
echo "Target IP address: $target_ip"
echo "Port: $port"

# Run iperf3 client in reverse mode with UDP indefinitely, using specified bandwidth and formatting output in Mbits
iperf3 -c "$target_ip" -u -R -p "$port" ${bandwidth:+-b "$bandwidth"} -t 0 -f m | while read -r line; do
    timestamp=$(date +"%Y-%m-%d %H:%M:%S.%3N")
    
    # Extracting bitrate, jitter, and lost packets from the iperf3 output.
    if [[ $line =~ \"bits_per_second\":([0-9.]+) ]]; then
        bitrate="${BASH_REMATCH[1]}"
    fi
    
    if [[ $line =~ \"jitter_ms\":([0-9.]+) ]]; then
        jitter="${BASH_REMATCH[1]}"
    fi
    
    if [[ $line =~ \"lost_packets\":([0-9]+) ]]; then
        lost_packets="${BASH_REMATCH[1]}"
        total_packets=$(echo "$lost_packets + $(grep 'Total datagrams' <<<"$line" | awk '{print $NF}')" | bc)
        lost_percentage=$(echo "scale=2; ($lost_packets / $total_packets) * 100" | bc)
    fi
    
    # Insert all metrics into the database in one query when all values are available.
    if [[ -n "$bitrate" && -n "$jitter" && -n "$lost_percentage" ]]; then
        mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "INSERT INTO iperf_results (timestamp, bitrate, jitter, lost_percentage) VALUES ('$timestamp', $bitrate, $jitter, $lost_percentage);"
        # Reset variables after insertion to avoid duplicate entries.
        bitrate=""
        jitter=""
        lost_percentage=""
    fi
done

