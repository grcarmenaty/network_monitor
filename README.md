# Network Monitor

A comprehensive network monitoring tool that uses iperf3, ping, and custom scripts to measure network performance and detect interruptions.

## Features

- Measure network throughput using iperf3
- Monitor network latency using ping
- Detect and log network interruptions
- Simulate periodic network disconnections
- Configurable settings with command-line options or default configuration file
- Easy installation and uninstallation process

## Prerequisites

- Linux-based operating system
- Root or sudo access
- Git (for cloning the repository)

## Installation

1. Clone the repository:

```
git clone https://github.com/grcarmenaty/network_monitor.git
cd network_monitor
```

2. Run the setup script with root privileges:

```
sudo ./setup.sh
```

This script will:
- Install required dependencies (iperf3, MySQL, Grafana, jq)
- Set up the MySQL database
- Configure Grafana
- Install the network monitoring scripts

3. Follow the prompts to configure the local and (optionally) remote database settings.

## Usage

After installation, you can run the network monitor using the `network_monitor` command:

```
network_monitor [OPTIONS]
```

### Options

- `-i <interface>`: Specify the network interface to use
- `-t <target_ip>`: Specify the target IP address
- `-p <port>`: Specify the port for iperf3 (default: 5050)
- `-b <bandwidth>`: Specify the bandwidth for iperf3
- `-d`: Create a default.conf file with current settings
- `-u`: Uninstall the network monitor
- `-a`: Used with -u, uninstall all associated programs
- `-s`: Simulate periodic disconnections
- `-h, --help`: Display help message

### Examples

1. Run with specific interface and target IP:

```
network_monitor -i eth0 -t 192.168.1.100
```

2. Create a default configuration file:

```
network_monitor -i eth0 -t 192.168.1.100 -p 5201 -b 100M -d
```

3. Run with simulated disconnections:

```
network_monitor -i eth0 -t 192.168.1.100 -s
```

4. Display help:

```
network_monitor -h
```

## Uninstallation

To uninstall the network monitor:

```
network_monitor -u
```

To uninstall the network monitor and all associated programs:

```
network_monitor -u -a
```

## Accessing Results

- The network monitoring results are stored in the MySQL database configured during installation.
- You can view the results using the Grafana dashboard installed at `http://localhost:3000`.

## Contributing

This project is not being actively maintained. I will do my best to look into pull requests, but if you see I'm slower than you'd like, feel free to fork the project.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
