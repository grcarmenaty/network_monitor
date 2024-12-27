#!/bin/bash

# Check if the script is being run as superuser
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as superuser. Please use sudo."
    exit 1
fi

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

    echo "setup.conf file created with user inputs in /opt/network_monitor/."
else
    echo "setup.conf file already exists in the network_monitor folder. Copying to /opt/network_monitor/."
    cp network_monitor/setup.conf /opt/network_monitor/setup.conf
fi

# Source the setup.conf file
source /opt/network_monitor/setup.conf

# Check if jq is installed
if ! command -v jq &> /dev/null
then
    echo "jq is not installed. Installing jq..."
    apt-get update
    apt-get install -y jq
    echo "jq installation complete."
else
    echo "jq is already installed."
fi

# Ensure MySQL is installed and running
if ! command -v mysql &> /dev/null
then
    echo "MySQL is not installed. Installing MySQL..."
    apt-get update
    apt-get install -y mysql-server
    echo "MySQL installation complete."
fi

# Start and enable MySQL service
echo "Starting and enabling MySQL service..."
systemctl start mysql
systemctl enable mysql

# Configure MySQL for remote access
mysql_config_path="/etc/mysql/mysql.conf.d/mysqld.cnf"
if [ -f "$mysql_config_path" ]; then
    # Replace bind-address line or add it if not present
    sed -i '/bind-address/c\bind-address = 0.0.0.0' "$mysql_config_path"
    if ! grep -q "bind-address" "$mysql_config_path"; then
        echo "bind-address = 0.0.0.0" >> "$mysql_config_path"
    fi
    echo "MySQL configuration updated for remote access."
else
    echo "MySQL configuration file not found at $mysql_config_path"
fi

# Restart MySQL service to apply changes
systemctl restart mysql

# Create database and user with remote access privileges
mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"
mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'%';"
mysql -e "FLUSH PRIVILEGES;"

echo "MySQL user '$DB_USER' created with remote access privileges."

# Check if iperf3 is installed
if ! command -v iperf3 &> /dev/null
then
    echo "iperf3 is not installed. Installing iperf3..."
    apt-get update
    apt-get install -y iperf3
    echo "iperf3 installation complete."
else
    echo "iperf3 is already installed."
fi

# Check if Grafana is installed
if ! command -v grafana-server &> /dev/null
then
    echo "Grafana is not installed. Installing Grafana..."
    
    # Install prerequisites
    apt-get install -y apt-transport-https software-properties-common wget

    # Add Grafana GPG key
    mkdir -p /etc/apt/keyrings/
    wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg > /dev/null

    # Add Grafana repository
    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee -a /etc/apt/sources.list.d/grafana.list

    # Update package list
    apt-get update

    # Install Grafana
    apt-get install -y grafana

    # Start and enable Grafana service
    systemctl start grafana-server
    systemctl enable grafana-server

    echo "Grafana installation complete."
else
    echo "Grafana is already installed."
fi

# Create the necessary tables
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
"

# Copy all scripts from the network_monitor folder to /opt/network_monitor/
cp network_monitor/*.sh /opt/network_monitor/

# Make all scripts executable
chmod +x /opt/network_monitor/*.sh

# Create symbolic link to server_launcher.sh
ln -sf /opt/network_monitor/server_launcher.sh /usr/local/bin/network_monitor

# Function to add Grafana data source
add_grafana_datasource() {
    local name=$1
    local type=$2
    local url=$3
    local database=$4
    local user=$5
    local password=$6

    curl -X POST -H "Content-Type: application/json" -H "Accept: application/json" -d '{
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
    }' http://admin:admin@localhost:3000/api/datasources

    echo "Restarting Grafana service..."
    systemctl restart grafana-server

    echo "Waiting for Grafana to restart..."
    while ! curl -s http://localhost:3000 > /dev/null; do
        sleep 1
    done
    echo "Grafana has restarted successfully."
}

# Wait for Grafana to start
echo "Waiting for Grafana to start..."
sleep 10

# Add the local database as a data source in Grafana
echo "Adding local database as a Grafana data source..."
add_grafana_datasource "LocalNetworkMonitor" "mysql" "localhost:3306" "$DB_NAME" "$DB_USER" "$DB_PASS"

if [[ $ADD_REMOTE == "y" || $ADD_REMOTE == "Y" ]]; then
    # Add the remote database as a data source in Grafana
    echo "Adding remote database as a Grafana data source..."
    add_grafana_datasource "RemoteNetworkMonitor" "mysql" "$REMOTE_DB_IP:$REMOTE_DB_PORT" "$REMOTE_DB_NAME" "$REMOTE_DB_USER" "$REMOTE_DB_PASS"
fi

# Path to the Grafana dashboards folder
grafana_dashboards_folder="grafana_dashboards"

# Choose the appropriate dashboard file
if [[ $ADD_REMOTE == "y" || $ADD_REMOTE == "Y" ]]; then
    dashboard_file="network_monitor_remote.json"
else
    dashboard_file="network_monitor_dashboard.json"
fi

dashboard_path="$grafana_dashboards_folder/$dashboard_file"

# Check if the dashboard file exists
if [ -f "$dashboard_path" ]; then
    # Update the dashboard JSON with correct data source UIDs
    local_ds_uid=$(curl -s -H "Accept: application/json" -H "Content-Type: application/json" http://admin:admin@localhost:3000/api/datasources/name/LocalNetworkMonitor | jq -r '.uid')
    
    # Update LocalNetworkMonitor UID in the dashboard JSON
    sed -i 's/"uid": "LocalNetworkMonitor"/"uid": "'"$local_ds_uid"'"/' "$dashboard_path"
    
    if [[ $ADD_REMOTE == "y" || $ADD_REMOTE == "Y" ]]; then
        remote_ds_uid=$(curl -s -H "Accept: application/json" -H "Content-Type: application/json" http://admin:admin@localhost:3000/api/datasources/name/RemoteNetworkMonitor | jq -r '.uid')
        # Update RemoteNetworkMonitor UID in the dashboard JSON
        sed -i 's/"uid": "RemoteNetworkMonitor"/"uid": "'"$remote_ds_uid"'"/' "$dashboard_path"
    fi

    # Add the dashboard to Grafana using Grafana's HTTP API
    curl -X POST -H "Content-Type: application/json" -H "Accept: application/json" -d "@$dashboard_path" http://admin:admin@localhost:3000/api/dashboards/import
    echo "Dashboard $dashboard_file added successfully to Grafana."
else
    echo "Error: $dashboard_file not found in the $grafana_dashboards_folder folder."
fi

echo "Setup complete. The network monitoring scripts have been copied to /opt/network_monitor/."
echo "A symbolic link 'network_monitor' has been created in /usr/local/bin/."
echo "Database $DB_NAME has been created with user $DB_USER and the necessary tables."
echo "Grafana has been installed and started. You can access it at http://localhost:3000"
echo "Default Grafana login credentials are admin/admin. You will be prompted to change the password on first login."
echo "A Grafana data source for the local database has been added."
if [[ $ADD_REMOTE == "y" || $ADD_REMOTE == "Y" ]]; then
    echo "A Grafana data source for the remote database has also been added."
fi
echo "You can now run the network monitoring by typing 'network_monitor' from anywhere in the terminal."
