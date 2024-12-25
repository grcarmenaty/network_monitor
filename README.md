# Network Monitor

This tool monitors network performance using iperf3 and ping, storing results in a MySQL database and visualizing them with Grafana.

## Installation

1. Clone the repository:

```
git clone https://github.com/grcarmenaty/network_monitor.git
cd network_monitor
```

2. Navigate to the network_monitor folder:

```
cd network_monitor
```

3. Run the setup script:

```
sudo ./setup.sh
```

This script will:
- Install MySQL, iperf3, and Grafana if not already installed
- Create a MySQL database and user
- Install the network monitoring script
- Configure Grafana with the appropriate data source(s)
- Import the Grafana dashboard

4. Follow the prompts to configure the local database and optionally add a remote database.

## Usage

1. Run the network monitoring tool:

```
network_monitor -i <interface> -t <target_ip> [-b <bandwidth>] [-p <port>]
```

- `-i`: Network interface to use
- `-t`: Target IP address
- `-b`: (Optional) Bandwidth limit for iperf3
- `-p`: (Optional) Port to use for iperf3 (default: 5050)

2. The tool will start an iperf3 server and wait for you to confirm that an iperf3 server is running on the target IP.

3. Once confirmed, it will begin monitoring and storing results in the database.

4. Access the Grafana dashboard at `http://localhost:3000` to view the results.
- Default login: admin/admin (you'll be prompted to change on first login)

5. To stop monitoring, use Ctrl+C.

## Configuration

If you want to automate the setup process, you can create a `setup.conf` file in the `network_monitor` folder with the following content:

```
DB_NAME=your_database_name
DB_USER=your_database_user
DB_PASS=your_database_password
ADD_REMOTE=y
REMOTE_DB_IP=remote_ip_address
REMOTE_DB_PORT=remote_port
REMOTE_DB_NAME=remote_database_name
REMOTE_DB_USER=remote_database_user
REMOTE_DB_PASS=remote_database_password
```

Adjust the values according to your needs. If `setup.conf` is present, the setup script will use these values instead of prompting for input.

## Troubleshooting

- If you encounter permission issues, ensure you're running the setup script with sudo.
- Check MySQL and Grafana logs if you experience database or visualization issues.
- Verify that iperf3 is installed and running correctly on both the local and target machines.

For more detailed information or to report issues, please visit the [GitHub repository](https://github.com/grcarmenaty/network_monitor).
