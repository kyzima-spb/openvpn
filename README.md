OpenVPN systemd-nspawn container 
================================

- [Introduction](#introduction)
- [How to install a container?](#how-to-install-a-container)
  - [Automatic installation](#automatic-installation)
  - [Manual installation](#manual-installation)
- [How to uninstall a container?](#how-to-uninstall-a-container)
- [How to Choose the Right VPS?](#how-to-choose-the-right-vps)
  - [Minimum System Requirements for Choosing a VPS](#minimum-system-requirements-for-choosing-a-vps)
  - [What I Used and Can Recommend](#what-i-used-and-can-recommend)
- [Commands for Working with Clients](#commands-for-working-with-clients)

## Introduction

**OpenVPN systemd-nspawn container** is an isolated environment
created with the systemd-nspawn containerization technology,
where an OpenVPN server is deployed and running.
This approach allows the VPN server to operate in a separate environment,
isolated from the host system, while preserving configuration flexibility and access to network resources.

Using `systemd-nspawn` as the container mechanism simplifies process management, integrates seamlessly with `systemd`,
and provides the ability to restrict access to the file system, network interfaces, and privileges.
This makes the VPN configuration more secure and manageable, especially in scenarios where you need to:

* run a VPN in a separate environment without affecting the host system;
* use different VPN configurations in parallel;
* test VPN connections in an isolated environment;
* separate routes and traffic across different network stacks.

## How to install a container?

**Log in to the system using SSH**:
the hosting provider usually provides the server’s IP address, login, and password.
All commands should be executed as the `root` user or with `sudo`.

### Automatic installation

```shell
# Installing the container with default parameters
# The OpenVPN configuration file needs to be imported into the OpenVPN Connect application
wget -qO- https://kyzima-spb.github.io/openvpn/installer.sh | \
  sudo bash > client.ovpn

# You can set a password, in which case the configuration will be saved in a ZIP archive
wget -qO- https://kyzima-spb.github.io/openvpn/installer.sh | \
  sudo bash -s -- --password 'very secret' > client.zip

# You can specify your own name for the container
wget -qO- https://kyzima-spb.github.io/openvpn/installer.sh | \
  sudo bash -s -- -n vpn > client.ovpn

# You can specify a domain or a fixed port
wget -qO- https://kyzima-spb.github.io/openvpn/installer.sh | \
  sudo bash -s -- --remote example.com -p 1194 > client.ovpn

# Or, if you need to use the TCP protocol
wget -qO- https://kyzima-spb.github.io/openvpn/installer.sh | \
  sudo bash -s -- --proto tcp > client.ovpn

# For more details, see the help for the install command
wget -qO- https://kyzima-spb.github.io/openvpn/installer.sh | \
  sudo bash -s -- install -h
```

All configuration files, certificates, and keys can be copied from the server to your computer
using FileZilla (Windows, macOS, Linux) or WinSCP (Windows only) over the **SFTP** protocol.

If you haven’t changed the directory after logging in, by default it is the user’s home directory.
For the root user, this is `/root`; for other users, it is `/home/<USERNAME>`.

On Linux, you can archive all the files and download them from the server with the command:

```shell
whoami  # root
pwd     # /root
tar -czf /root/credentials.tar.gz <PATH_1> <PATH_2> <PATH_N>
scp <USER>@<PUBLIC_IP>:/root/credentials.tar.gz <DEST_PATH>
```

### Manual installation



## How to uninstall a container?

To remove the container, the image, and all related files, run:

```shell
wget -qO- https://kyzima-spb.github.io/openvpn/installer.sh | \
  sudo bash -s -- uninstall
```

If a different name was specified during installation, run:

```shell
wget -qO- https://kyzima-spb.github.io/openvpn/installer.sh | \
  sudo bash -s -- uninstall -n vpn
```

## How to Choose the Right VPS?

Selecting the right VPS starts with two key factors:
the server’s physical location and its latency (ping).
These have the biggest impact on performance and user experience.

As for system requirements, only a few basics really matter.
Below you’ll find the minimum specs you should pay attention to -
everything else plays only a minor role and won’t significantly affect your setup.

### Minimum System Requirements for Choosing a VPS

* A dedicated server or VPS with XEN or KVM virtualization (OpenVZ is not suitable)
* A dedicated IPv4 address
* At least 1 GB of RAM
* At least 5 GB of disk space
* A Linux distribution with `systemd-machined` available (Debian 12/13 recommended)
* Unlimited traffic, or as much as possible =)

### What I Used and Can Recommend

> All links are referral links!!!

* [RoboVPS](https://www.robovps.biz/?ref=39155)
  * Usage period: 17.04.2022 - 17.10.2023
  * Very good and stable hosting, support responds quickly
    It was the optimal option in terms of price/quality until the prices increased
  * Available locations: USA, Germany, Netherlands, Finland and Russia

* [HOSTING RUSSIA](https://hosting-russia.ru/?p=37512)
  * Usage period: 17.10.2023 - present
  * Very good and stable hosting, support responds relatively quickly,
    but there was a case when it was simply unavailable during a DDoS attack
  * Available locations: Germany, Netherlands and Russia
  * You can pay with a 6- or 12-month discount

* [TimeWeb](https://timeweb.cloud/?i=127787)
  * Usage period: 20.06.2025 - present
  * Very good and stable hosting, support responds quickly
  * You can pay with a 3-, 6- or 12-month discount
  * Available locations: Germany, Netherlands, Kazakhstan and Russia

* [аéза]
  * **Account with a small balance was deleted without warning**
  * Tested on 21.02.2024 in USA, London, and Netherlands locations
  * Hourly billing

## Commands for Working with Clients

Client management for OpenVPN inside the container is handled by the `client-util` script.
For more details, see the help documentation. Here are a few examples for common use cases.

Commands can be executed inside the container:

```shell
# To login the container, use the command:
machinectl shell <CONTAINER_NAME>
# Inside the container, view the help for the command:
client-util -h
```

Or from the host:

```shell
systemd-run -q --wait --pipe -M openvpn client-util -h
```

To add a new client named `phone`, run the command:

```shell
systemd-run -q --wait --pipe -M openvpn client-util generate phone
```

To recreate the certificate and key for an existing client, use the `--revoke` argument.
This will revoke the previously issued certificate and key:

```shell
systemd-run -q --wait --pipe -M openvpn client-util generate phone --revoke
```

Deleting a client is not supported, but you can revoke the certificate and key issued to them.
To do this, run the command:

```shell
systemd-run -q --wait --pipe -M openvpn client-util revoke phone
```

To generate a configuration file for the OpenVPN Connect application, run the command:

```shell
systemd-run -q --wait --pipe -M openvpn client-util show phone > phone.ovpn
```

If the port was not explicitly specified during installation, a random available port will be used.
Inside the container, this port is unknown, so when generating OVPN files,
you need to explicitly specify the port:

```shell
VPN_PORT="$(grep '^Port=' /etc/systemd/nspawn/openvpn.nspawn | awk -F: '{print $2}' | head -1)"
systemd-run -q --wait --pipe -M openvpn client-util show phone -p "$VPN_PORT" > phone.ovpn
```
