#!/bin/bash

# Source the setup.conf file
source /opt/network_monitor/setup.conf

# Initialize variables
target_ip=${REMOTE_DB_IP:-""}
interface=""

# Parse command-line options
while getopts "t:i:" opt; do
  case $opt in
    t)
      target_ip="$OPTARG"
      ;;
    i)
      interface="$OPTARG"
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

# Check if interface is provided
if [ -z "$interface" ]; then
  echo "Error: Interface not specified. Use -i flag to specify the interface."
  exit 1
fi

echo "Monitoring interruptions for target IP: $target_ip"
echo "Using interface: $interface"

# Function to check connectivity and record interruptions
check_connectivity() {
    local start_time=0
    local disconnected=false
    local consecutive_failures=0
    local consecutive_successes=0
    local failure_threshold=5  # Require 5 consecutive failures to declare disconnection
    local recovery_threshold=3  # Require 3 consecutive successes to declare recovery
    local min_interruption_duration=2.0  # Only record interruptions longer than 2 seconds

    echo "🔍 Interruption detection parameters:"
    echo "   - Failure threshold: $failure_threshold consecutive ping failures"
    echo "   - Recovery threshold: $recovery_threshold consecutive ping successes"
    echo "   - Minimum interruption duration: $min_interruption_duration seconds"
    echo "   - Ping interval: 1 second"
    echo ""

    while true; do
        if ping -c 1 -W 2 -I "$interface" "$target_ip" &> /dev/null; then
            # Ping successful
            consecutive_failures=0
            consecutive_successes=$((consecutive_successes + 1))
            
            if $disconnected && [ $consecutive_successes -ge $recovery_threshold ]; then
                local end_time=$(date +%s.%N)
                # Calculate interruption time using awk for floating point arithmetic
                local interruption_time=$(awk "BEGIN {printf \"%.3f\", $end_time - $start_time}")
                
                # Only record significant interruptions (longer than minimum threshold)
                if [ -n "$interruption_time" ] && [ "$(awk "BEGIN {print ($interruption_time >= $min_interruption_duration)}")" = "1" ]; then
                    local timestamp=$(date +"%Y-%m-%d %H:%M:%S.%3N")
                    echo "🔴 REAL INTERRUPTION DETECTED: Connection restored after $interruption_time seconds"
                    echo "📝 Recording interruption in database..."
                    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "INSERT INTO interruptions (timestamp, interruption_time) VALUES ('$timestamp', $interruption_time);" 2>/dev/null
                    if [ $? -eq 0 ]; then
                        echo "✅ Interruption recorded successfully"
                    else
                        echo "❌ Failed to record interruption in database"
                    fi
                else
                    echo "🟡 Brief connectivity issue resolved ($interruption_time seconds) - not recording (below $min_interruption_duration second threshold)"
                fi
                disconnected=false
                consecutive_successes=0
            elif ! $disconnected; then
                # Connection is stable, just reset counters silently
                consecutive_successes=0
            fi
        else
            # Ping failed
            consecutive_successes=0
            consecutive_failures=$((consecutive_failures + 1))
            
            if ! $disconnected && [ $consecutive_failures -ge $failure_threshold ]; then
                start_time=$(date +%s.%N)
                disconnected=true
                echo "🔴 Connection lost at $(date) after $consecutive_failures consecutive ping failures. Monitoring for recovery..."
            elif ! $disconnected; then
                echo "🟡 Ping failure $consecutive_failures/$failure_threshold (not yet considered disconnected)"
            fi
        fi
        sleep 1  # Check every second instead of every 0.1 seconds
    done
}

# Start the connectivity check
check_connectivity
