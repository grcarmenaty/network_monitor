#!/bin/bash

# Initialize variables
interface=""
local_ip=""
target_ip=""
bandwidth=""
port=5050
db_user="network_user"
db_password="n3tw0rk_p@ssw0rd"
db_name="NETWORK_MONITOR_DB"

# Parse command-line options
while getopts "i:t:b:p:" opt; do
  case $opt in
    i)
      interface="$OPTARG"
      ;;
    t)
      target_ip="$OPTARG"
      ;;
    b)
      bandwidth="$OPTARG"
      ;;
    p)
      port="$OPTARG"
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

# Check if target IP is provided
if [ -z "$target_ip" ]; then
  echo "Error: Target IP not specified. Use -t flag to specify the target IP."
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
echo "Bandwidth: ${bandwidth:-unlimited}"
echo "Port: $port"

# Function to check connectivity and record interruptions
check_connectivity() {
    local start_time=0
    local disconnected=false

    while true; do
        if ping -c 1 -W 1 "$target_ip" &> /dev/null; then
            if $disconnected; then
                local end_time=$(date +%s.%N)
                local interruption_time=$(echo "$end_time - $start_time" | bc)
                local timestamp=$(date +"%Y-%m-%d %H:%M:%S.%3N")
                mysql -u "$db_user" -p"$db_password" "$db_name" -e "INSERT INTO interruptions (timestamp, interruption_time) VALUES ('$timestamp', $interruption_time);"
                disconnected=false
                echo "Connection restored. Interruption lasted $interruption_time seconds."
            fi
        else
            if ! $disconnected; then
                start_time=$(date +%s.%N)
                disconnected=true
                echo "Connection lost at $(date). Recording interruption..."
            fi
        fi
        sleep 0.1
    done
}

# Function to check connectivity and record interruptions
check_connectivity() {
    local start_time=0
    local disconnected=false

    while true; do
        if ping -c 1 -W 1 "$target_ip" &> /dev/null; then
            if $disconnected; then
                local end_time=$(date +%s.%N)
                local interruption_time=$(echo "$end_time - $start_time" | bc)
                local timestamp=$(date +"%Y-%m-%d %H:%M:%S.%3N")
                mysql -u "$db_user" -p"$db_password" "$db_name" -e "INSERT INTO interruptions (timestamp, interruption_time) VALUES ('$timestamp', $interruption_time);"
                disconnected=false
                echo "Connection restored. Interruption lasted $interruption_time seconds."
            fi
        else
            if ! $disconnected; then
                start_time=$(date +%s.%N)
                disconnected=true
                echo "Connection lost at $(date). Recording interruption..."
            fi
        fi
        sleep 0.1
    done
}

# Start iperf3 server
echo "Starting iperf3 server on port $port..."
iperf3 -s -p $port &
server_pid=$!

echo "Press enter when you are sure there is an iPerf3 server running on target IP listening on port $port"
read -r

check_connectivity &
connectivity_pid=$!

# Prepare iperf3 command
iperf_cmd="iperf3 -c $target_ip -u -R -p $port -B $local_ip -t 0 -f m -i 1"
if [ -n "$bandwidth" ]; then
  iperf_cmd="$iperf_cmd -b $bandwidth"
fi

# Run iperf3 with parsing and database insertion
$iperf_cmd | while IFS= read -r line; do
    timestamp=$(date +"%Y-%m-%d %H:%M:%S.%3N")
    if [[ $line =~ \[.*\][[:space:]]+([0-9.]+)[[:space:]]Mbits/sec[[:space:]]+([0-9.]+)[[:space:]]ms[[:space:]]+([0-9]+)/([0-9]+)[[:space:]]\(([0-9.]+)%\) ]]; then
        bitrate="${BASH_REMATCH[1]}"
        jitter="${BASH_REMATCH[2]}"
        lost_percentage="${BASH_REMATCH[5]}"
        mysql -u "$db_user" -p"$db_password" "$db_name" -e "INSERT INTO iperf_results (timestamp, bitrate, jitter, lost_percentage) VALUES ('$timestamp', $bitrate, $jitter, $lost_percentage);"
    fi
done &

# Store the PID of the iperf3 background process
iperf_pid=$!

# Run ping with parsing and database insertion
ping -i 1 -W 1 -I "$interface" "$target_ip" | while IFS= read -r line; do
    timestamp=$(date +"%Y-%m-%d %H:%M:%S.%3N")
    if [[ $line =~ time=([0-9.]+)[[:space:]]ms ]]; then
        latency="${BASH_REMATCH[1]}"
        mysql -u "$db_user" -p"$db_password" "$db_name" -e "INSERT INTO ping_results (timestamp, latency) VALUES ('$timestamp', $latency);"
    fi
done &

# Store the PID of the ping background process
ping_pid=$!

echo "iperf3 and ping are running. Press Ctrl+C to stop."

# Wait for user interrupt
trap "kill $server_pid $iperf_pid $ping_pid $connectivity_pid; exit" INT TERM

# Wait for all background processes
wait $iperf_pid $ping_pid $connectivity_pid
