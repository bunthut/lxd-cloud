Full personal cloud
===================

# This project are split in multiple subproject

To select the storage backend for LXD, edit `config/03_OTHER_VARS` and set `LXD_STORAGE_DRIVER` to either `btrfs` (default) or `zfs`.
The scripts automatically detect the driver of an existing `default` storage pool
and reuse it. To switch to a different backend, remove any conflicting pools
first (for example `lxc storage delete default`) before rerunning the
initialization.

Please see :
+ [Installation and lxd configuration](https://github.com/AlbanVidal/install_conf_lxd)
+ [Deploy of Nextcloud](https://github.com/AlbanVidal/deploy_nextcloud)
+ [Deploy of Wordpress](https://github.com/AlbanVidal/deploy_wordpress)
+ [Deploy of Icinga2](https://github.com/AlbanVidal/deploy_icinga)

## Installation

The installation now runs in two stages. Invoke `install.sh` with your desired
components. The first run prepares the host and installs LXD, then asks you to
log out so the `lxd` group membership can take effect. After logging back in,
re-run the same command to deploy the selected containers.

Run all components:

```
./install.sh --all   # first run
# log out and log back in
./install.sh --all   # second run to finish
```

Install only specific components by combining flags:

```
./install.sh --nextcloud --mariadb
./install.sh --smtp
```

Run `./install.sh --help` to see all available options.

Specify custom domain names when running the installer:

```
./install.sh --nextcloud \
    --fqdn cloud.example.com \
    --collabora-fqdn office.example.com \
    --smtp-fqdn smtp.example.com
```

Skip DNS validation when records are not yet configured:


Forward additional host ports with the `--port-forward` flag. The format is
`HOST_PORT:CONTAINER[:CONTAINER_PORT]`. For example, to expose SMTP on port 25
and a custom service on port 8080:

```
./install.sh --all \
    --port-forward 25:smtp \
    --port-forward 8080:rvprx:8081
```

Ports 80 and 443 are automatically mapped to the `rvprx` container. Use
`--use-lxd-proxy` if you prefer LXD proxy devices instead of iptables rules for
the port forwarding.

 =======
```
./install.sh --skip-dns-check
```

Use custom ports for the reverse proxy and Collabora:

```
./install.sh --all \
    --http-port 8080 \
    --https-port 8443 \
    --collabora-port 9980
```

## Manually create the `privNet` profile

The installer normally creates a `privNet` profile for the internal network. If
needed, you can create it yourself with:

```
lxc profile create privNet
lxc profile device add privNet ethPrivate nic nictype=bridged parent=lxdbrINT name=ethPrivate
```

This profile connects the container interface `ethPrivate` to the bridge
`lxdbrINT` for backend communication.

