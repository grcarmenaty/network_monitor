#!/bin/bash

# Source the setup.conf file
source /opt/network_monitor/setup.conf

# Initialize variables
interface=""
port=5050
target_ip=${REMOTE_DB_IP:-""}  # Default to REMOTE_DB_IP
bandwidth=""
create_default=false

# Function to create default.conf
create_default_conf() {
    cat > /opt/network_monitor/default.conf << EOF
INTERFACE=$interface
TARGET_IP=$target_ip
PORT=$port
BANDWIDTH=$bandwidth
EOF
    echo "Created default.conf with current settings."
}

# Check if default.conf exists and source it if no flags are passed
if [ $# -eq 0 ] && [ -f "/opt/network_monitor/default.conf" ]; then
    source /opt/network_monitor/default.conf
    echo "Using settings from default.conf"
fi

# Parse command-line options
while getopts "i:t:p:b:d" opt; do
  case $opt in
    i) interface="$OPTARG" ;;
    t) target_ip="$OPTARG" ;;
    p) port="$OPTARG" ;;
    b) bandwidth="$OPTARG" ;;
    d) create_default=true ;;
    \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
    :) echo "Option -$OPTARG requires an argument." >&2; exit 1 ;;
  esac
done

# Create default.conf if -d flag is passed
if [ "$create_default" = true ]; then
    create_default_conf
    exit 0
fi

# Check if interface is provided
if [ -z "$interface" ]; then
  echo "Error: Interface not specified. Use -i flag to specify the interface."
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
echo "Starting iperf3 server on port $port..."

# Start iperf3 server in the background
iperf3 -s -p "$port" &
server_pid=$!

echo "Press enter when you are sure there is an iPerf3 server running on target IP listening on port $port"
read -r

# Launch other scripts in the background
./iperf_client.sh -i "$interface" -t "$target_ip" -p "$port" ${bandwidth:+-b "$bandwidth"} &
./ping_client.sh -i "$interface" -t "$target_ip" &
./interruption_monitor.sh -i "$interface" -t "$target_ip" &

# Wait for all background processes to finish
wait $server_pid

echo "Iperf3 server stopped."
