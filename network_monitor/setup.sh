#!/bin/bash

# Check if the script is being run as superuser
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as superuser. Please use sudo."
    exit 1
fi

# Check if main.sh exists in the current directory
if [ ! -f "main.sh" ]; then
    echo "Error: main.sh not found in the current directory."
    exit 1
fi

# Function to read value from setup.conf
read_config() {
    if [ -f "setup.conf" ]; then
        grep "^$1=" setup.conf | cut -d '=' -f 2-
    fi
}

# Check if setup.conf exists and read values
if [ -f "setup.conf" ]; then
    echo "Found setup.conf file. Reading configuration..."
    DB_NAME=$(read_config "DB_NAME")
    DB_USER=$(read_config "DB_USER")
    DB_PASS=$(read_config "DB_PASS")
    ADD_REMOTE=$(read_config "ADD_REMOTE")
    REMOTE_DB_IP=$(read_config "REMOTE_DB_IP")
    REMOTE_DB_PORT=$(read_config "REMOTE_DB_PORT")
    REMOTE_DB_NAME=$(read_config "REMOTE_DB_NAME")
    REMOTE_DB_USER=$(read_config "REMOTE_DB_USER")
    REMOTE_DB_PASS=$(read_config "REMOTE_DB_PASS")
fi

# Check if MySQL is installed
if ! command -v mysql &> /dev/null
then
    echo "MySQL is not installed. Installing MySQL..."
    apt-get update
    apt-get install -y mysql-server
    echo "MySQL installation complete."
else
    echo "MySQL is already installed."
fi

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

# Prompt for local database configuration if not in setup.conf
if [ -z "$DB_NAME" ]; then
    while true; do
        read -p "Enter local database name: " DB_NAME
        if [ -n "$DB_NAME" ]; then
            break
        else
            echo "Database name cannot be empty. Please try again."
        fi
    done
fi

if [ -z "$DB_USER" ]; then
    while true; do
        read -p "Enter local database user: " DB_USER
        if [ -n "$DB_USER" ]; then
            break
        else
            echo "Database user cannot be empty. Please try again."
        fi
    done
fi

if [ -z "$DB_PASS" ]; then
    while true; do
        read -s -p "Enter local database password: " DB_PASS
        echo
        if [ -n "$DB_PASS" ]; then
            break
        else
            echo "Database password cannot be empty. Please try again."
        fi
    done
fi

# Create the local database and user
mysql -e "
CREATE DATABASE IF NOT EXISTS $DB_NAME;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
"

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

# Create the /opt/network_monitor directory
mkdir -p /opt/network_monitor

# Copy main.sh to /opt/network_monitor/
cp main.sh /opt/network_monitor/main.sh

# Update main.sh with the provided database credentials
sed -i "s/db_user=\"network_user\"/db_user=\"$DB_USER\"/" /opt/network_monitor/main.sh
sed -i "s/db_password=\"n3tw0rk_p@ssw0rd\"/db_password=\"$DB_PASS\"/" /opt/network_monitor/main.sh
sed -i "s/db_name=\"NETWORK_MONITOR_DB\"/db_name=\"$DB_NAME\"/" /opt/network_monitor/main.sh

# Make the main.sh script executable
chmod +x /opt/network_monitor/main.sh

# Create symbolic link to make the script accessible as a command
ln -sf /opt/network_monitor/main.sh /usr/local/bin/network_monitor
chmod +x /usr/local/bin/network_monitor

# Add the local database as a data source in Grafana
grafana-cli admin data-source add --type mysql --name "LocalNetworkMonitor" --url "localhost:3306" --database "$DB_NAME" --user "$DB_USER" --password "$DB_PASS"

# Ask if user wants to add a remote database (if not specified in setup.conf)
if [ -z "$ADD_REMOTE" ]; then
    read -p "Do you want to add a remote database? (y/n): " ADD_REMOTE
fi

if [[ $ADD_REMOTE == "y" || $ADD_REMOTE == "Y" ]]; then
    # Prompt for remote database configuration if not in setup.conf
    if [ -z "$REMOTE_DB_IP" ]; then
        while true; do
            read -p "Enter remote database IP: " REMOTE_DB_IP
            if [ -n "$REMOTE_DB_IP" ]; then
                break
            else
                echo "Remote database IP cannot be empty. Please try again."
            fi
        done
    fi

    if [ -z "$REMOTE_DB_PORT" ]; then
        read -p "Enter remote database port (default 3306): " REMOTE_DB_PORT
        REMOTE_DB_PORT=${REMOTE_DB_PORT:-3306}
    fi
    
    if [ -z "$REMOTE_DB_NAME" ]; then
        while true; do
            read -p "Enter remote database name: " REMOTE_DB_NAME
            if [ -n "$REMOTE_DB_NAME" ]; then
                break
            else
                echo "Remote database name cannot be empty. Please try again."
            fi
        done
    fi

    if [ -z "$REMOTE_DB_USER" ]; then
        while true; do
            read -p "Enter remote database user: " REMOTE_DB_USER
            if [ -n "$REMOTE_DB_USER" ]; then
                break
            else
                echo "Remote database user cannot be empty. Please try again."
            fi
        done
    fi

    if [ -z "$REMOTE_DB_PASS" ]; then
        while true; do
            read -s -p "Enter remote database password: " REMOTE_DB_PASS
            echo
            if [ -n "$REMOTE_DB_PASS" ]; then
                break
            else
                echo "Remote database password cannot be empty. Please try again."
            fi
        done
    fi

    # Add the remote database as a data source in Grafana
    grafana-cli admin data-source add --type mysql --name "RemoteNetworkMonitor" --url "$REMOTE_DB_IP:$REMOTE_DB_PORT" --database "$REMOTE_DB_NAME" --user "$REMOTE_DB_USER" --password "$REMOTE_DB_PASS"
    
    echo "Remote database added as a data source in Grafana."
fi

echo "Setup complete. The main.sh script has been copied to /opt/network_monitor/."
echo "A symbolic link 'network_monitor' has been created in /usr/local/bin/."
echo "Local database $DB_NAME has been created with user $DB_USER and the necessary tables."
echo "Grafana has been installed and started. You can access it at http://localhost:3000"
echo "Default Grafana login credentials are admin/admin. You will be prompted to change the password on first login."
echo "A Grafana data source for the local database has been added."
if [[ $ADD_REMOTE == "y" || $ADD_REMOTE == "Y" ]]; then
    echo "A Grafana data source for the remote database has also been added."
fi
echo "You can now run the script by typing 'network_monitor' from anywhere in the terminal."
