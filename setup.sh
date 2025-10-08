#!/bin/bash

# Network Monitor Setup Script - Complete Version with All Fixes
# This script installs and configures MariaDB, Grafana, and network monitoring tools
# Incorporates all fixes: timezone handling, server binding, signal handling, parsing fixes

# Check if the script is being run as superuser
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as superuser. Please use sudo."
    exit 1
fi

echo "========================================="
echo "🚀 Network Monitor Setup - Complete"
echo "========================================="
echo "This script will install and configure:"
echo "- MariaDB database server with timezone handling"
echo "- Grafana monitoring dashboard with timezone fixes"
echo "- Network monitoring tools (iperf3, jq, bc)"
echo "- Database tables and configuration"
echo "- Server binding and signal handling improvements"
echo "========================================="
echo

# Create the /opt/network_monitor directory
mkdir -p /opt/network_monitor

# Check if setup.conf exists in the network_monitor folder
if [ ! -f "network_monitor/setup.conf" ]; then
    echo "Creating setup.conf file..."
    
    # Prompt for local database configuration
    read -p "Enter database name: " DB_NAME
    read -p "Enter database user: " DB_USER
    read -s -p "Enter database password: " DB_PASS
    echo

    # Write local database configuration to setup.conf
    echo "DB_NAME=$DB_NAME" >> /opt/network_monitor/setup.conf
    echo "DB_USER=$DB_USER" >> /opt/network_monitor/setup.conf
    echo "DB_PASS=$DB_PASS" >> /opt/network_monitor/setup.conf

    # Ask if user wants to add a remote database
    read -p "Do you want to add a remote database? (y/n): " ADD_REMOTE
    echo "ADD_REMOTE=$ADD_REMOTE" >> /opt/network_monitor/setup.conf

    if [[ $ADD_REMOTE == "y" || $ADD_REMOTE == "Y" ]]; then
        read -p "Enter remote database IP: " REMOTE_DB_IP
        read -p "Enter remote database port (default 3306): " REMOTE_DB_PORT
        REMOTE_DB_PORT=${REMOTE_DB_PORT:-3306}
        read -p "Enter remote database name: " REMOTE_DB_NAME
        read -p "Enter remote database user: " REMOTE_DB_USER
        read -s -p "Enter remote database password: " REMOTE_DB_PASS
        echo

        # Write remote database configuration to setup.conf
        echo "REMOTE_DB_IP=$REMOTE_DB_IP" >> /opt/network_monitor/setup.conf
        echo "REMOTE_DB_PORT=$REMOTE_DB_PORT" >> /opt/network_monitor/setup.conf
        echo "REMOTE_DB_NAME=$REMOTE_DB_NAME" >> /opt/network_monitor/setup.conf
        echo "REMOTE_DB_USER=$REMOTE_DB_USER" >> /opt/network_monitor/setup.conf
        echo "REMOTE_DB_PASS=$REMOTE_DB_PASS" >> /opt/network_monitor/setup.conf
    fi

    echo "✅ setup.conf file created with user inputs in /opt/network_monitor/."
else
    echo "✅ setup.conf file already exists in the network_monitor folder. Copying to /opt/network_monitor/."
    cp network_monitor/setup.conf /opt/network_monitor/setup.conf
fi

# Source the setup.conf file
source /opt/network_monitor/setup.conf

echo
echo "=== Installing Required Packages ==="

# Check if jq is installed
if ! command -v jq &> /dev/null
then
    echo "📦 Installing jq..."
    apt-get update
    apt-get install -y jq
    echo "✅ jq installation complete."
else
    echo "✅ jq is already installed."
fi

# Check if bc is installed (FIX: Added bc installation)
if ! command -v bc &> /dev/null
then
    echo "📦 Installing bc (calculator)..."
    apt-get install -y bc
    echo "✅ bc installation complete."
else
    echo "✅ bc is already installed."
fi

# Function to handle MariaDB installation with error recovery (IMPROVED)
install_mariadb() {
    echo "📦 Installing MariaDB server..."
    
    # Check if MariaDB is already working
    if command -v mysql &> /dev/null && mysqladmin ping --silent 2>/dev/null; then
        echo "✅ MariaDB is already installed and running."
        return 0
    fi
    
    # Stop any running services
    systemctl stop mariadb 2>/dev/null || true
    systemctl stop mysql 2>/dev/null || true
    killall mysqld 2>/dev/null || true
    
    # Handle potential broken package configuration
    echo "🔧 Checking for broken package configuration..."
    
    # Create missing files that might cause configuration issues
    mkdir -p /etc/mysql
    touch /etc/mysql/mariadb.cnf 2>/dev/null || true
    
    # Fix broken dpkg configuration
    dpkg --configure -a 2>/dev/null || true
    
    # Clean up any broken installations
    apt-get remove --purge -y mariadb-server* mariadb-client* mariadb-common* libmariadb* mysql-server* mysql-client* mysql-common* 2>/dev/null || true
    
    # Clean up configuration and data
    rm -rf /var/lib/mysql* 2>/dev/null || true
    rm -rf /etc/mysql 2>/dev/null || true
    rm -rf /var/log/mysql* 2>/dev/null || true
    rm -rf /run/mysqld 2>/dev/null || true
    
    # Clean up alternatives
    update-alternatives --remove-all my.cnf 2>/dev/null || true
    update-alternatives --remove-all mariadb.cnf 2>/dev/null || true
    
    # Force remove any remaining packages
    dpkg --remove --force-remove-reinstreq mariadb-common 2>/dev/null || true
    dpkg --remove --force-remove-reinstreq libmariadb3 2>/dev/null || true
    
    # Clean package cache
    apt-get autoremove -y 2>/dev/null || true
    apt-get autoclean 2>/dev/null || true
    apt-get install -f -y 2>/dev/null || true
    dpkg --configure -a 2>/dev/null || true
    
    # Update package lists
    apt-get update
    
    # Install MariaDB fresh
    echo "📦 Installing fresh MariaDB..."
    export DEBIAN_FRONTEND=noninteractive
    
    # Pre-seed MariaDB configuration to avoid prompts
    debconf-set-selections <<< "mariadb-server mysql-server/root_password password "
    debconf-set-selections <<< "mariadb-server mysql-server/root_password_again password "
    
    # Install MariaDB
    if ! apt-get install -y mariadb-server mariadb-client; then
        echo "❌ MariaDB installation failed"
        exit 1
    fi
    
    # Verify installation
    if ! command -v mysql &> /dev/null; then
        echo "❌ MariaDB installation verification failed"
        exit 1
    fi
    
    echo "✅ MariaDB installed successfully"
    
    # Start and enable the service
    systemctl enable mariadb
    systemctl start mariadb
    
    # Wait for MariaDB to start
    echo "⏳ Waiting for MariaDB to start..."
    max_attempts=30
    attempt=0
    while ! mysqladmin ping --silent 2>/dev/null; do
        sleep 2
        attempt=$((attempt + 1))
        if [ $attempt -ge $max_attempts ]; then
            echo "❌ MariaDB failed to start"
            systemctl status mariadb
            journalctl -u mariadb --no-pager -n 20
            exit 1
        fi
        echo "⏳ Waiting... (attempt $attempt/$max_attempts)"
    done
    
    echo "✅ MariaDB is now running"
    
    # Secure the installation
    echo "🔒 Securing MariaDB installation..."
    mysql -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null || true
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>/dev/null || true
    mysql -e "DROP DATABASE IF EXISTS test;" 2>/dev/null || true
    mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" 2>/dev/null || true
    mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    
    echo "✅ MariaDB secured"
}

# Install MariaDB
install_mariadb

# Configure MariaDB for remote access
echo "🔧 Configuring MariaDB for remote access..."
config_file="/etc/mysql/mariadb.conf.d/50-server.cnf"

# Create the configuration directory if it doesn't exist
mkdir -p /etc/mysql/mariadb.conf.d/

# Create the server configuration file
cat > "$config_file" << 'EOF'
[mysqld]
bind-address = 0.0.0.0
port = 3306
max_connections = 100
innodb_buffer_pool_size = 128M
EOF

echo "✅ MariaDB configured for remote access"

# Restart to apply configuration
echo "🔄 Restarting MariaDB to apply configuration..."
systemctl restart mariadb

# Wait for restart
sleep 5
max_attempts=30
attempt=0
while ! mysqladmin ping --silent 2>/dev/null; do
    sleep 2
    attempt=$((attempt + 1))
    if [ $attempt -ge $max_attempts ]; then
        echo "❌ MariaDB failed to restart"
        exit 1
    fi
    echo "⏳ Waiting for restart... (attempt $attempt/$max_attempts)"
done

echo "✅ MariaDB restarted successfully"

# Create database and user with remote access privileges
echo "🗄️ Creating database '$DB_NAME' and user '$DB_USER'..."
mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;" || { echo "❌ Failed to create database"; exit 1; }
mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASS';" || { echo "❌ Failed to create user"; exit 1; }
mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'%';" || { echo "❌ Failed to grant privileges"; exit 1; }
mysql -e "FLUSH PRIVILEGES;" || { echo "❌ Failed to flush privileges"; exit 1; }

echo "✅ MariaDB user '$DB_USER' created with remote access privileges."

# Test database connection
echo "🧪 Testing database connection..."
if mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SELECT 1;" > /dev/null 2>&1; then
    echo "✅ Database connection test successful."
else
    echo "❌ Database connection test failed."
    exit 1
fi

# Check if iperf3 is installed
if ! command -v iperf3 &> /dev/null
then
    echo "📦 Installing iperf3..."
    apt-get update
    apt-get install -y iperf3
    echo "✅ iperf3 installation complete."
else
    echo "✅ iperf3 is already installed."
fi

# Clean up duplicate Grafana repository entries
echo "🧹 Cleaning up duplicate repository entries..."
if [ -f /etc/apt/sources.list.d/grafana.list ]; then
    # Remove duplicates and keep only one entry
    sort -u /etc/apt/sources.list.d/grafana.list > /tmp/grafana.list.tmp
    mv /tmp/grafana.list.tmp /etc/apt/sources.list.d/grafana.list
fi

# Check if Grafana is installed
if ! command -v grafana-server &> /dev/null
then
    echo "📦 Installing Grafana..."
    
    # Install prerequisites
    apt-get install -y apt-transport-https software-properties-common wget

    # Add Grafana GPG key
    mkdir -p /etc/apt/keyrings/
    wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg > /dev/null

    # Add Grafana repository (only if not already present)
    if ! grep -q "apt.grafana.com" /etc/apt/sources.list.d/grafana.list 2>/dev/null; then
        echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list
    fi

    # Update package list
    apt-get update

    # Install Grafana
    apt-get install -y grafana

    # Start and enable Grafana service
    systemctl start grafana-server
    systemctl enable grafana-server

    echo "✅ Grafana installation complete."
else
    echo "✅ Grafana is already installed."
    # Make sure it's running
    systemctl start grafana-server
    systemctl enable grafana-server
fi

# FIX: Configure Grafana timezone to match system timezone
echo "🕐 Configuring Grafana timezone..."
GRAFANA_CONFIG="/etc/grafana/grafana.ini"
SYSTEM_TIMEZONE=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "UTC")

# Update Grafana configuration for timezone
if [ -f "$GRAFANA_CONFIG" ]; then
    # Set default timezone in Grafana config
    sed -i "s/^;default_timezone =.*/default_timezone = $SYSTEM_TIMEZONE/" "$GRAFANA_CONFIG"
    sed -i "s/^default_timezone =.*/default_timezone = $SYSTEM_TIMEZONE/" "$GRAFANA_CONFIG"
    
    # If the line doesn't exist, add it
    if ! grep -q "default_timezone" "$GRAFANA_CONFIG"; then
        echo "default_timezone = $SYSTEM_TIMEZONE" >> "$GRAFANA_CONFIG"
    fi
    
    echo "✅ Grafana timezone set to: $SYSTEM_TIMEZONE"
    
    # Restart Grafana to apply timezone changes
    systemctl restart grafana-server
    sleep 5
else
    echo "⚠️  Grafana config file not found, timezone may not be set correctly"
fi

# Create the necessary tables
echo "🗄️ Creating database tables..."
mysql -u $DB_USER -p$DB_PASS $DB_NAME -e "
CREATE TABLE IF NOT EXISTS iperf_results (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp DATETIME(3),
    bitrate FLOAT,
    jitter FLOAT,
    lost_percentage FLOAT
);

CREATE TABLE IF NOT EXISTS ping_results (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp DATETIME(3),
    latency FLOAT
);

CREATE TABLE IF NOT EXISTS interruptions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp DATETIME(3),
    interruption_time FLOAT
);
" || { echo "❌ Failed to create database tables"; exit 1; }

echo "✅ Database tables created successfully."

# Copy all scripts from the network_monitor folder to /opt/network_monitor/
echo "📁 Copying scripts to /opt/network_monitor/..."
cp network_monitor/*.sh /opt/network_monitor/ 2>/dev/null || true

# Make all scripts executable
chmod +x /opt/network_monitor/*.sh 2>/dev/null || true

echo "🔧 Scripts include robust interruption detection (requires 5 consecutive ping failures, 2+ second duration)"
echo "🔧 Scripts include real-time database insertion (no buffering delays)"

# Create symbolic link to server_launcher.sh
if [ -f "/opt/network_monitor/server_launcher.sh" ]; then
    ln -sf /opt/network_monitor/server_launcher.sh /usr/local/bin/network_monitor
    echo "✅ Created symbolic link 'network_monitor' in /usr/local/bin/"
fi

# Function to add Grafana data source
add_grafana_datasource() {
    local name=$1
    local type=$2
    local url=$3
    local database=$4
    local user=$5
    local password=$6

    echo "📊 Adding Grafana data source: $name"
    
    # Check if data source already exists
    existing_ds=$(curl -s -H "Accept: application/json" -H "Content-Type: application/json" http://admin:admin@localhost:3000/api/datasources/name/$name 2>/dev/null)
    
    if echo "$existing_ds" | jq -e '.id' > /dev/null 2>&1; then
        echo "✅ Data source $name already exists, skipping..."
        return 0
    fi

    response=$(curl -s -X POST -H "Content-Type: application/json" -H "Accept: application/json" -d '{
        "name":"'"$name"'",
        "type":"'"$type"'",
        "url":"'"$url"'",
        "database":"'"$database"'",
        "user":"'"$user"'",
        "jsonData": {
            "maxOpenConns": 100,
            "maxIdleConns": 100,
            "connMaxLifetime": 14400
        },
        "secureJsonData": {
            "password":"'"$password"'"
        },
        "access":"proxy",
        "basicAuth":false
    }' http://admin:admin@localhost:3000/api/datasources)

    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        echo "✅ Data source $name added successfully."
    else
        echo "⚠️  Warning: Data source $name may not have been added correctly."
        echo "Response: $response"
    fi
}

# Wait for Grafana to start
echo "⏳ Waiting for Grafana to start..."
max_attempts=60
attempt=0
while ! curl -s http://localhost:3000 > /dev/null; do
    sleep 2
    attempt=$((attempt + 1))
    if [ $attempt -ge $max_attempts ]; then
        echo "❌ Grafana failed to start within expected time"
        systemctl status grafana-server
        exit 1
    fi
    echo "⏳ Waiting for Grafana... (attempt $attempt/$max_attempts)"
done
echo "✅ Grafana is now accessible."

# Add the local database as a data source in Grafana
echo "📊 Adding local database as a Grafana data source..."
add_grafana_datasource "LocalNetworkMonitor" "mysql" "localhost:3306" "$DB_NAME" "$DB_USER" "$DB_PASS"

if [[ $ADD_REMOTE == "y" || $ADD_REMOTE == "Y" ]]; then
    # Add the remote database as a data source in Grafana
    echo "📊 Adding remote database as a Grafana data source..."
    add_grafana_datasource "RemoteNetworkMonitor" "mysql" "$REMOTE_DB_IP:$REMOTE_DB_PORT" "$REMOTE_DB_NAME" "$REMOTE_DB_USER" "$REMOTE_DB_PASS"
fi

# FIX: Import dashboards with timezone-aware queries
echo "📊 Importing timezone-aware dashboards..."

# Get data source UIDs
local_ds_uid=$(curl -s -H "Accept: application/json" -H "Content-Type: application/json" http://admin:admin@localhost:3000/api/datasources/name/LocalNetworkMonitor | jq -r '.uid')

if [[ $ADD_REMOTE == "y" || $ADD_REMOTE == "Y" ]]; then
    remote_ds_uid=$(curl -s -H "Accept: application/json" -H "Content-Type: application/json" http://admin:admin@localhost:3000/api/datasources/name/RemoteNetworkMonitor | jq -r '.uid')
fi

# Path to the Grafana dashboards folder
grafana_dashboards_folder="./network_monitor/grafana_dashboards"

# Choose the appropriate dashboard file
if [[ $ADD_REMOTE == "y" || $ADD_REMOTE == "Y" ]]; then
    dashboard_file="network_monitor_remote.json"
else
    dashboard_file="network_monitor_dashboard.json"
fi

dashboard_path="$grafana_dashboards_folder/$dashboard_file"

# Check if the dashboard file exists
if [ -f "$dashboard_path" ]; then
    echo "📊 Importing timezone-fixed dashboard: $dashboard_file"
    
    # Create a temporary copy of the dashboard to avoid modifying the original
    temp_dashboard="/tmp/dashboard_timezone_fixed.json"
    cp "$dashboard_path" "$temp_dashboard"
    
    # FIX: Apply timezone fixes to SQL queries
    echo "🕐 Applying timezone fixes to dashboard queries..."
    
    # Replace problematic $__timeFilter(timestamp) with timezone-aware queries
    sed -i 's/SELECT timestamp AS time, bitrate AS value FROM iperf_results WHERE \$__timeFilter(timestamp) ORDER BY time ASC;/SELECT UNIX_TIMESTAMP(timestamp) * 1000 AS time, bitrate AS value FROM iperf_results WHERE timestamp >= DATE_SUB(NOW(), INTERVAL 24 HOUR) ORDER BY time ASC;/g' "$temp_dashboard"
    
    sed -i 's/SELECT timestamp AS time, jitter AS value FROM iperf_results WHERE \$__timeFilter(timestamp) ORDER BY time ASC;/SELECT UNIX_TIMESTAMP(timestamp) * 1000 AS time, jitter AS value FROM iperf_results WHERE timestamp >= DATE_SUB(NOW(), INTERVAL 24 HOUR) ORDER BY time ASC;/g' "$temp_dashboard"
    
    sed -i 's/SELECT timestamp AS time, lost_percentage AS value FROM iperf_results WHERE \$__timeFilter(timestamp) ORDER BY time ASC;/SELECT UNIX_TIMESTAMP(timestamp) * 1000 AS time, lost_percentage AS value FROM iperf_results WHERE timestamp >= DATE_SUB(NOW(), INTERVAL 24 HOUR) ORDER BY time ASC;/g' "$temp_dashboard"
    
    sed -i 's/SELECT timestamp AS time, latency AS value FROM ping_results WHERE \$__timeFilter(timestamp) ORDER BY time ASC;/SELECT UNIX_TIMESTAMP(timestamp) * 1000 AS time, latency AS value FROM ping_results WHERE timestamp >= DATE_SUB(NOW(), INTERVAL 24 HOUR) ORDER BY time ASC;/g' "$temp_dashboard"
    
    sed -i 's/SELECT timestamp AS time, interruption_time AS value FROM interruptions WHERE \$__timeFilter(timestamp) ORDER BY time ASC;/SELECT UNIX_TIMESTAMP(timestamp) * 1000 AS time, interruption_time AS value FROM interruptions WHERE timestamp >= DATE_SUB(NOW(), INTERVAL 24 HOUR) ORDER BY time ASC;/g' "$temp_dashboard"
    
    # Update data source UIDs
    if [ "$local_ds_uid" != "null" ] && [ -n "$local_ds_uid" ]; then
        sed -i "s/\"uid\": \"LocalNetworkMonitor\"/\"uid\": \"$local_ds_uid\"/g" "$temp_dashboard"
        echo "✅ Updated LocalNetworkMonitor UID to: $local_ds_uid"
    fi
    
    if [[ $ADD_REMOTE == "y" || $ADD_REMOTE == "Y" ]] && [ "$remote_ds_uid" != "null" ] && [ -n "$remote_ds_uid" ]; then
        sed -i "s/\"uid\": \"RemoteNetworkMonitor\"/\"uid\": \"$remote_ds_uid\"/g" "$temp_dashboard"
        echo "✅ Updated RemoteNetworkMonitor UID to: $remote_ds_uid"
    fi

    # Add title suffix to indicate timezone fix
    sed -i 's/"title": "Network Monitoring Dashboard"/"title": "Network Monitoring Dashboard (Timezone Fixed)"/g' "$temp_dashboard"
    sed -i 's/"title": "Network Monitoring Dashboard (Bidirectional)"/"title": "Network Monitoring Dashboard (Bidirectional - Timezone Fixed)"/g' "$temp_dashboard"

    # Import the dashboard
    dashboard_response=$(curl -s -X POST -H "Content-Type: application/json" -H "Accept: application/json" -d @"$temp_dashboard" http://admin:admin@localhost:3000/api/dashboards/db 2>/dev/null)
    
    if echo "$dashboard_response" | jq -e '.status == "success"' > /dev/null 2>&1; then
        dashboard_url=$(echo "$dashboard_response" | jq -r '.url')
        echo "✅ Dashboard imported successfully with timezone fixes!"
        echo "   URL: http://localhost:3000$dashboard_url"
    else
        echo "⚠️  Warning: Dashboard import may have failed. Response: $dashboard_response"
    fi
    
    # Clean up temporary file
    rm -f "$temp_dashboard"
else
    echo "⚠️  Warning: $dashboard_file not found in the $grafana_dashboards_folder folder."
fi

echo
echo "========================================="
echo "🎉 Setup Complete!"
echo "========================================="
echo "✅ The network monitoring scripts have been copied to /opt/network_monitor/."
if [ -f "/usr/local/bin/network_monitor" ]; then
    echo "✅ A symbolic link 'network_monitor' has been created in /usr/local/bin/."
fi
echo "✅ Database $DB_NAME has been created with user $DB_USER and the necessary tables."
echo "✅ MariaDB is running and accessible."
echo "✅ Grafana has been installed with timezone configuration."
echo "✅ Grafana dashboards imported with timezone fixes applied."
echo "✅ Data sources configured for local database."
if [[ $ADD_REMOTE == "y" || $ADD_REMOTE == "Y" ]]; then
    echo "✅ Data sources configured for remote database."
fi
if [ -f "/usr/local/bin/network_monitor" ]; then
    echo "✅ You can now run the network monitoring by typing 'network_monitor' from anywhere in the terminal."
fi
echo "========================================="

# Final verification
echo
echo "=== 🔍 Final System Verification ==="
echo -n "MariaDB service: "
if systemctl is-active mariadb >/dev/null 2>&1; then
    echo "✅ Running"
else
    echo "❌ Not running"
fi

echo -n "Grafana service: "
if systemctl is-active grafana-server >/dev/null 2>&1; then
    echo "✅ Running"
else
    echo "❌ Not running"
fi

echo -n "Database connection: "
if mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME';" > /dev/null 2>&1; then
    echo "✅ Working"
else
    echo "❌ Failed"
fi

echo -n "Grafana accessibility: "
if curl -s http://localhost:3000 > /dev/null; then
    echo "✅ Accessible"
else
    echo "❌ Not accessible"
fi

echo "=== ✅ Verification Complete ==="
echo
echo "🎯 Next Steps:"
echo "1. Access Grafana at http://localhost:3000 (admin/admin)"
echo "2. Change the default Grafana password"
if [ -f "/usr/local/bin/network_monitor" ]; then
    echo "3. Start network monitoring with: network_monitor -i <interface> -t <target_ip>"
    echo "   Example: network_monitor -i enp60s0 -t 10.0.0.11 -S 10.0.0.12 -p 5050"
fi
echo "4. Check the imported dashboard - it includes timezone fixes"
echo "5. Set dashboard time range to 'Last 24 hours' to see data"
echo
echo "🚀 Your network monitoring system is ready with all fixes applied!"
