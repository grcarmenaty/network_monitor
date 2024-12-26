#!/bin/bash

# Source the setup.conf file
source /opt/network_monitor/setup.conf

# Initialize variables
target_ip=${REMOTE_DB_IP:-""}

# Parse command-line options
while getopts "t:" opt; do
  case $opt in
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

# Check if target IP is provided or available from setup.conf
if [ -z "$target_ip" ]; then
  echo "Error: Target IP not specified and not found in setup.conf."
  exit 1
fi

echo "Monitoring interruptions for target IP: $target_ip"

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
                mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "INSERT INTO interruptions (timestamp, interruption_time) VALUES ('$timestamp', $interruption_time);"
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

# Start the connectivity check
check_connectivity

