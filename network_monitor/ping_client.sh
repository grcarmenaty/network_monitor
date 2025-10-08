#!/bin/bash

# Source the setup.conf file
source /opt/network_monitor/setup.conf

# Initialize variables
interface=""
target_ip=${REMOTE_DB_IP:-""}

# Parse command-line options
while getopts "i:t:" opt; do
  case $opt in
    i)
      interface="$OPTARG"
      ;;
    t)
      target_ip="$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

# Check if interface is provided
if [ -z "$interface" ]; then
  echo "Error: Interface not specified. Use -i flag to specify the interface."
  exit 1
fi

# Check if target IP is provided or available from setup.conf
if [ -z "$target_ip" ]; then
  echo "Error: Target IP not specified and not found in setup.conf."
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

# Run ping with parsing and database insertion (unbuffered for real-time processing)
stdbuf -oL -eL ping -i 1 -W 1 -I "$interface" "$target_ip" | while IFS= read -r line; do
    timestamp=$(date +"%Y-%m-%d %H:%M:%S.%3N")
    if [[ $line =~ time=([0-9.]+)[[:space:]]ms ]]; then
        latency="${BASH_REMATCH[1]}"
        mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "INSERT INTO ping_results (timestamp, latency) VALUES ('$timestamp', $latency);"
    fi
done

