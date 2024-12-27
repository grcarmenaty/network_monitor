#!/bin/bash

# Set the script directory
SCRIPT_DIR="/opt/network_monitor"

# Source the setup.conf file
source "$SCRIPT_DIR/setup.conf"

# Initialize variables
interface=""
port=5050
target_ip=${REMOTE_DB_IP:-""}  # Default to REMOTE_DB_IP
bandwidth=""
create_default=false
uninstall=false
uninstall_all=false
simulate_disconnections=false

# Function to display help
show_help() {
    echo "Usage: network_monitor [OPTIONS]"
    echo "Network monitoring tool with iperf3, ping, and connection interruption detection."
    echo
    echo "Options:"
    echo "  -i <interface>   Specify the network interface to use"
    echo "  -t <target_ip>   Specify the target IP address"
    echo "  -p <port>        Specify the port for iperf3 (default: 5050)"
    echo "  -b <bandwidth>   Specify the bandwidth for iperf3"
    echo "  -d               Create a default.conf file with current settings"
    echo "  -u               Uninstall the network monitor"
    echo "  -a               Used with -u, uninstall all associated programs"
    echo "  -s               Simulate periodic disconnections"
    echo "  -h, --help       Display this help message"
    echo
    echo "Example:"
    echo "  network_monitor -i eth0 -t 192.168.1.100 -p 5201 -b 100M"
}

# Function to create default.conf
create_default_conf() {
    cat > "$SCRIPT_DIR/default.conf" << EOF
INTERFACE=$interface
TARGET_IP=$target_ip
PORT=$port
BANDWIDTH=$bandwidth
EOF
    echo "Created default.conf with current settings."
}

# Function to uninstall
uninstall() {
    echo "Uninstalling network monitor..."
    
    # Stop any running processes
    pkill -f "iperf_client.sh"
    pkill -f "ping_client.sh"
    pkill -f "interruption_monitor.sh"
    pkill -f "iperf3 -s"

    # Call the uninstall.sh script
    if [ "$uninstall_all" = true ]; then
        "$SCRIPT_DIR/uninstall.sh" -a
    else
        "$SCRIPT_DIR/uninstall.sh"
    fi

    echo "Network monitor uninstalled."
    exit 0
}

# Function to simulate disconnections
simulate_disconnections() {
    while true; do
        sleep 60  # Wait for 1 minute
        duration=$((RANDOM % 6 + 5))  # Random number between 5 and 10
        echo "Simulating disconnection for $duration seconds"
        sudo "$SCRIPT_DIR/disconnection_test.sh" -t "$target_ip" &
        disconnect_pid=$!
        sleep $duration
        sudo kill -INT $disconnect_pid
        wait $disconnect_pid 2>/dev/null
    done
}

# Check if default.conf exists and source it if no flags are passed
if [ $# -eq 0 ] && [ -f "$SCRIPT_DIR/default.conf" ]; then
    source "$SCRIPT_DIR/default.conf"
    echo "Using settings from default.conf"
fi

# Parse command-line options
while [[ $# -gt 0 ]]; do
    case $1 in
        -i) interface="$2"; shift 2 ;;
        -t) target_ip="$2"; shift 2 ;;
        -p) port="$2"; shift 2 ;;
        -b) bandwidth="$2"; shift 2 ;;
        -d) create_default=true; shift ;;
        -u) uninstall=true; shift ;;
        -a) uninstall_all=true; shift ;;
        -s) simulate_disconnections=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Unknown option: $1" >&2; show_help; exit 1 ;;
    esac
done

# Uninstall if -u flag is passed
if [ "$uninstall" = true ]; then
    uninstall
fi

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
"$SCRIPT_DIR/iperf_client.sh" -i "$interface" -t "$target_ip" -p "$port" ${bandwidth:+-b "$bandwidth"} &
"$SCRIPT_DIR/ping_client.sh" -i "$interface" -t "$target_ip" &
"$SCRIPT_DIR/interruption_monitor.sh" -i "$interface" -t "$target_ip" &

# Start simulating disconnections if -s flag is passed
if [ "$simulate_disconnections" = true ]; then
    simulate_disconnections &
    simulate_pid=$!
fi

# Wait for all background processes to finish
wait $server_pid

# Kill the simulation process if it's running
if [ "$simulate_disconnections" = true ]; then
    kill $simulate_pid 2>/dev/null
fi

echo "Iperf3 server stopped."
