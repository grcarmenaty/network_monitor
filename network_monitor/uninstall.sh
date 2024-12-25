#!/bin/bash

# Check if the script is being run as superuser
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as superuser. Please use sudo."
    exit 1
fi

# Check if setup.conf exists
if [ ! -f "/opt/network_monitor/setup.conf" ]; then
    echo "Error: setup.conf not found in /opt/network_monitor/. Cannot proceed with uninstallation."
    exit 1
fi

# Source the setup.conf file
source /opt/network_monitor/setup.conf

# Remove local database and user
echo "Removing local MySQL database and user..."
mysql -e "DROP DATABASE IF EXISTS $DB_NAME;"
mysql -e "DROP USER IF EXISTS '$DB_USER'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Remove Grafana data source for local database
echo "Removing Grafana data source for local database..."
grafana-cli admin data-sources delete LocalNetworkMonitor

# If remote database was added, remove its data source
if [[ $ADD_REMOTE == "y" || $ADD_REMOTE == "Y" ]]; then
    echo "Removing Grafana data source for remote database..."
    grafana-cli admin data-sources delete RemoteNetworkMonitor
fi

# Remove Grafana dashboard
echo "Removing Grafana dashboard..."
DASHBOARD_UID=$(curl -s -H "Content-Type: application/json" -X GET http://localhost:3000/api/dashboards/db/network-monitoring-dashboard --user admin:admin | jq -r '.dashboard.uid')
if [ ! -z "$DASHBOARD_UID" ]; then
    curl -X DELETE http://localhost:3000/api/dashboards/uid/$DASHBOARD_UID --user admin:admin
fi

# Remove symbolic link
echo "Removing symbolic link..."
if [ -L "/usr/local/bin/network_monitor" ]; then
    rm /usr/local/bin/network_monitor
fi

# Remove network_monitor files
echo "Removing network_monitor files..."
rm -rf /opt/network_monitor

echo "Uninstallation complete. The following actions were performed:"
echo "- Removed local MySQL database $DB_NAME and user $DB_USER"
echo "- Removed Grafana data source for local database"
if [[ $ADD_REMOTE == "y" || $ADD_REMOTE == "Y" ]]; then
    echo "- Removed Grafana data source for remote database"
fi
echo "- Removed Grafana dashboard"
echo "- Removed symbolic link for network_monitor command"
echo "- Removed all files in /opt/network_monitor"
echo ""
echo "Note: MySQL, iperf3, and Grafana have not been uninstalled."
