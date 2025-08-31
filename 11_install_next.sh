#!/bin/bash

#
# BSD 3-Clause License
# 
# Copyright (c) 2018, Alban Vidal <alban.vidal@zordhak.fr>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
# 
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# 
# * Neither the name of the copyright holder nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

################################################################################
##########                    Define color to output:                 ########## 
################################################################################
_WHITE_="tput sgr0"
_RED_="tput setaf 1"
_GREEN_="tput setaf 2"
_ORANGE_="tput setaf 3"
################################################################################

# TODO
# - logrotate (all CT)
# - iptables isolateur: Deny !80 !443

# Load Vars
source config/00_VARS

# Load Network Vars
source config/01_NETWORK_VARS

# Load Resources Vars
source config/02_RESOURCES_VARS

# Load Other vars 
# - LXD_DEPORTED_DIR
# - DEBIAN_RELEASE
# - LXD_DEFAULT_STORAGE_TYPE
source config/03_OTHER_VARS

# Create temporary directory for this script
TMP_DIR=$(mktemp -d)
# Ensure the temporary directory is writable
if [ ! -w "$TMP_DIR" ]; then
    echo "$($_RED_)Temporary directory $TMP_DIR is not writable$($_WHITE_)"
    exit 1
fi
# Remove the temporary directory on exit
trap 'rm -rf "$TMP_DIR"' EXIT

################################################################################

# Determine which components to install. If no arguments are supplied, install
# all available components. Components correspond to container names used later
# in the script (smtp, rvprx, mariadb, cloud, collabora).
DEFAULT_COMPONENTS=(smtp rvprx mariadb cloud collabora)
if [ "$#" -eq 0 ]; then
    COMPONENTS=("${DEFAULT_COMPONENTS[@]}")
else
    COMPONENTS=("$@")
fi

has_component() {
    local comp
    for comp in "${COMPONENTS[@]}"; do
        [[ $comp == "$1" ]] && return 0
    done
    return 1
}

# Convenience variable for loops later
CT_LIST="${COMPONENTS[*]}"

################################################################################

# Exit if LXD is not installed
if ! which lxd >/dev/null;then
    echo "$($_RED_)LXD is not installed$($_WHITE_)"
    exit 1
fi

# LXD INIT
echo "$($_ORANGE_)LXD initialization$($_WHITE_)"
# Skip re-initialization when LXD is already configured
if lxc profile list >/dev/null 2>&1; then
    echo "$($_ORANGE_)LXD already initialized, using existing configuration$($_WHITE_)"

    # Ensure required LXD bridges exist when reusing an initialized setup
    if ! lxc network show lxdbrEXT >/dev/null 2>&1; then
        echo "$($_ORANGE_)Creating missing lxdbrEXT bridge$($_WHITE_)"
        if ! lxc network create lxdbrEXT \
            ipv4.address=${IP_LXD}/${CIDR} \
            ipv4.nat=true \
            ipv4.dhcp=true \
            ipv4.dhcp.ranges=${lxdbrEXT_DHCP_RANGE} \
            ipv6.address=none >/dev/null 2>&1; then
            echo "$($_RED_)Failed to create lxdbrEXT network$($_WHITE_)"
            exit 1
        fi
    fi

    if ! lxc network show lxdbrINT >/dev/null 2>&1; then
        echo "$($_ORANGE_)Creating missing lxdbrINT bridge$($_WHITE_)"
        if ! lxc network create lxdbrINT \
            ipv4.address=${IP_LXD_PRIV}/${CIDR} \
            ipv4.nat=false \
            ipv4.dhcp=false \
            ipv6.address=none >/dev/null 2>&1; then
            echo "$($_RED_)Failed to create lxdbrINT network$($_WHITE_)"
            exit 1
        fi
    fi
elif $LXD_INIT; then
    # Initializing of lxd
    cat << EOF | lxd init --preseed
# Daemon settings
config:
  images.auto_update_interval: 15

# Storage pools
$LXD_DEFAULT_STORAGE

# Network devices
networks:
- name: lxdbrEXT
  type: bridge
  config:
    ipv4.address: $IP_LXD/$CIDR
    ipv4.nat: "true"
    ipv4.dhcp: "true"
    ipv4.dhcp.ranges: $lxdbrEXT_DHCP_RANGE
    ipv6.address: none

- name: lxdbrINT
  type: bridge
  config:
    ipv4.address: $IP_LXD_PRIV/$CIDR
    ipv4.nat: "false"
    ipv4.dhcp: "false"
    ipv6.address: none

# Profiles
profiles:

- name: default
  description: "Default Net and storage"
  devices:
    ethPublic:
      name: eth0
      nictype: bridged
      parent: lxdbrEXT
      type: nic
    root:
      path: /
      pool: default
      type: disk

- name: privNet
  description: "Internal (backend) Network"
  devices:
    ethPrivate:
      name: ethPrivate
      nictype: bridged
      parent: lxdbrINT
      type: nic

- name: cpu-1
  description: "1 CPU"
  config:
    limits.cpu: "1"

- name: cpu-2
  description: "2 CPU"
  config:
    limits.cpu: "2"

- name: cpu-4
  description: "4 CPU"
  config:
    limits.cpu: "4"

- name: ram-256
  description: "256MB RAM"
  config:
    limits.memory: 256MB

- name: ram-512
  description: "512MB RAM"
  config:
    limits.memory: 512MB

- name: ram-1024
  description: "1GB RAM"
  config:
    limits.memory: 1GB

- name: ram-2048
  description: "2GB RAM"
  config:
    limits.memory: 2GB

- name: ram-4096
  description: "4GB RAM"
  config:
    limits.memory: 4GB
EOF
else
    echo "$($_ORANGE_)You have choose to not configure lxd$($_WHITE_)"
fi

# Ensure required LXD profiles exist
REQUIRED_PROFILES=("default" "privNet")
if has_component cloud; then
    REQUIRED_PROFILES+=("$LXC_PROFILE_cloud_CPU" "$LXC_PROFILE_cloud_MEM")
fi
if has_component collabora; then
    REQUIRED_PROFILES+=("$LXC_PROFILE_collabora_CPU" "$LXC_PROFILE_collabora_MEM")
fi
if has_component mariadb; then
    REQUIRED_PROFILES+=("$LXC_PROFILE_mariadb_CPU" "$LXC_PROFILE_mariadb_MEM")
fi
if has_component rvprx; then
    REQUIRED_PROFILES+=("$LXC_PROFILE_rvprx_CPU" "$LXC_PROFILE_rvprx_MEM")
fi
if has_component smtp; then
    REQUIRED_PROFILES+=("$LXC_PROFILE_smtp_CPU" "$LXC_PROFILE_smtp_MEM")
fi

# Create CPU, memory limit or special network profiles when missing
create_profile() {
    local prof="$1"
    case "$prof" in
        cpu-*)
            local cpu="${prof#cpu-}"
            lxc profile show "$prof" >/dev/null 2>&1 || \
                lxc profile create "$prof" >/dev/null 2>&1 || return 1
            lxc profile set "$prof" limits.cpu "$cpu" >/dev/null 2>&1 || return 1
            ;;
        ram-*)
            local mem="${prof#ram-}"
            if (( mem % 1024 == 0 )); then
                mem="$((mem/1024))GB"
            else
                mem="${mem}MB"
            fi
            lxc profile show "$prof" >/dev/null 2>&1 || \
                lxc profile create "$prof" >/dev/null 2>&1 || return 1
            lxc profile set "$prof" limits.memory "$mem" >/dev/null 2>&1 || return 1
            ;;
        privNet)
            # Network profile for backend bridge
            lxc profile show "$prof" >/dev/null 2>&1 || {
                lxc profile create "$prof" >/dev/null 2>&1 || return 1
            }
            # Ensure nic device exists
            lxc profile device show "$prof" ethPrivate >/dev/null 2>&1 || \
                lxc profile device add "$prof" ethPrivate nic nictype=bridged parent=lxdbrINT name=ethPrivate >/dev/null 2>&1 || return 1
            ;;
        *)
            return 1
            ;;
    esac
}

for profile in $(printf '%s\n' "${REQUIRED_PROFILES[@]}" | sort -u); do
    if ! lxc profile show "$profile" >/dev/null 2>&1; then
        if ! create_profile "$profile"; then
            echo "$($_RED_)LXD profile '$profile' is missing. Please fix LXD initialization before running this script.$($_WHITE_)"
            exit 1
        fi
    fi
done

NEED_TEMPLATE=false
for CT in $CT_LIST; do
    if ! lxc info "$CT" >/dev/null 2>&1; then
        NEED_TEMPLATE=true
        break
    fi
done

if $NEED_TEMPLATE; then

# TEMPLATE interfaces containers
cat << EOF > "$TMP_DIR/lxd_interfaces_TEMPLATE"
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address _IP_PUB_/_CIDR_
    gateway $IP_LXD

auto ethPrivate
iface ethPrivate inet static
    address _IP_PRIV_/_CIDR_
EOF

# TEMPLATE resolv.conf (see config/01_NETWORK_VARS to change nameserver)
cat << EOF > "$TMP_DIR/lxd_resolv.conf"
$RESOLV_CONF
EOF

################################################################################
#
# Create template container

lxc launch images:debian/$DEBIAN_RELEASE z-template --profile default --profile privNet
#lxc exec z-template -- bash -c "
#                                echo -e 'auto lo\\niface lo inet loopback\\n\\nauto ethPublic\\niface ethPublic inet dhcp' > /etc/network/interfaces
#                               "
#lxc restart z-template

echo "$($_ORANGE_)Wait dhcp...$($_WHITE_)"
sleep 5

################################################################################
#
# Configure template container

echo "$($_ORANGE_)Container TEMPLATE: Update, upgrade and install common packages$($_WHITE_)"


# Allow overriding the Python package version; default to python3
PYTHON_PACKAGE=${PYTHON_PACKAGE:-python3}

PACKAGES="git vim apt-utils bsd-mailx postfix ${PYTHON_PACKAGE} python-is-python3"


# Initial package installation in the template container
lxc exec z-template -- bash -c "
    apt-get update > /dev/null
    DEBIAN_FRONTEND=noninteractive apt-get -y install $PACKAGES > /dev/null
    DEBIAN_FRONTEND=noninteractive apt-get -y upgrade > /dev/null
    mkdir -p /srv/git/basic_config_debian
"

# Use local basic_config_debian instead of cloning from the Internet
lxc file push templates/basic_config_debian/auto_config.sh \
    z-template/srv/git/basic_config_debian/auto_config.sh

lxc exec z-template -- bash -c "
    # Setup config file for auto configuration
    > /srv/git/basic_config_debian/conf
    echo 'UNATTENDED_EMAIL=\"$TECH_ADMIN_EMAIL\"' >> /srv/git/basic_config_debian/conf
    echo 'GIT_USERNAME=\"$HOSTNAME\"'             >> /srv/git/basic_config_debian/conf
    echo 'GIT_EMAIL=\"root@$HOSTNAME\"'           >> /srv/git/basic_config_debian/conf
    echo 'SSH_EMAIL_ALERT=\"$TECH_ADMIN_EMAIL\"'  >> /srv/git/basic_config_debian/conf
    chmod +x /srv/git/basic_config_debian/auto_config.sh
    # Launch auto configuration script
    /srv/git/basic_config_debian/auto_config.sh
"

# Postfix default conf file
# Copy file in tmp becose « snap » is isoled, can't acess to root dir
cp /etc/postfix/main.cf "$TMP_DIR/template_postfix_main.cf"
lxc file push "$TMP_DIR/template_postfix_main.cf" z-template/etc/postfix/main.cf

# Copy /etc/crontab for Send crontab return to admin (TECH_ADMIN_EMAIL)
lxc file push /etc/crontab z-template/etc/crontab

lxc stop z-template --force

################################################################################

# Create all container from template
echo "$($_ORANGE_)Create and network configuration for selected containers$($_WHITE_)"
for CT in $CT_LIST ; do
    if lxc info "${CT}" >/dev/null 2>&1; then
        echo "$($_ORANGE_)Container ${CT} already exists, reusing$($_WHITE_)"
    else
        echo "$($_ORANGE_)Create ${CT}...$($_WHITE_)"
        lxc copy z-template "${CT}"
        lxc start "${CT}"
    fi
    IP_PUB="IP_${CT}"
    IP_PRIV="IP_${CT}_PRIV"
    sed -e "s/_IP_PUB_/${!IP_PUB}/" -e "s/_IP_PRIV_/${!IP_PRIV}/" -e "s/_CIDR_/$CIDR/" "$TMP_DIR/lxd_interfaces_TEMPLATE" > "$TMP_DIR/lxd_interfaces_${CT}"
    lxc file push "$TMP_DIR/lxd_interfaces_${CT}" ${CT}/etc/network/interfaces
    lxc file push "$TMP_DIR/lxd_resolv.conf" ${CT}/etc/resolv.conf
    lxc restart "${CT}" --force 2>/dev/null || lxc start "${CT}"
done

else
    echo "$($_ORANGE_)All selected containers already exist, skipping creation$($_WHITE_)"
fi

################################################################################

# Create and attach deported directory
echo "$($_ORANGE_)Create and attach deported directory ($LXD_DEPORTED_DIR/…)$($_WHITE_)"

if has_component rvprx; then
    ## RVPRX
    ## - Nginx configuration
    ## - letsencrypt certificates
    mkdir -p \
        $LXD_DEPORTED_DIR/rvprx/etc/nginx        \
        $LXD_DEPORTED_DIR/rvprx/etc/letsencrypt
    lxc config device add rvprx shared-rvprx disk path=/srv/lxd source=$LXD_DEPORTED_DIR/rvprx/
fi

if has_component cloud; then
    ## Cloud
    ## - Nextcloud html directory
    mkdir -p \
        $LXD_DEPORTED_DIR/cloud/var/www
    lxc config device add cloud shared-cloud disk path=/srv/lxd source=$LXD_DEPORTED_DIR/cloud/
fi

if has_component mariadb; then
    ## Mariadb
    ## - Tempory directory for MySQL dump
    mkdir -p \
        $LXD_DEPORTED_DIR/mariadb
    lxc config device add mariadb shared-mariadb disk path=/srv/lxd source=$LXD_DEPORTED_DIR/mariadb
fi

# Set mapped UID and GID to LXD deported directory
echo "$($_ORANGE_)Set mapped UID and GID to LXD deported directory ($LXD_DEPORTED_DIR)$($_WHITE_)"
chown -R 1000000:1000000 $LXD_DEPORTED_DIR/

################################################################################
#### CONTAINER CONFIGURATION
echo ""
echo "$($_GREEN_)CONTAINER CONFIGURATION$($_WHITE_)"
echo ""

if has_component smtp; then
    ############################################################
    #### SMTP
    ./containers/21_configure_smtp.sh
fi

if has_component rvprx; then
    ############################################################
    #### RVPRX
    ./containers/22_configure_rvprx.sh
fi

if has_component mariadb; then
    ############################################################
    #### MariaDB
    # Generate nextcloud database password
    MDP_nextcoud=$(openssl rand -base64 32)
    echo "$MDP_nextcoud" > /tmp/lxc_nextcloud_password
    ./containers/23_configure_mariadb.sh
fi

if has_component cloud; then
    ############################################################
    #### CLOUD
    ./containers/24_configure_cloud.sh
fi

if has_component mariadb; then
    # Delete nextcloud database password if created
    rm -f /tmp/lxc_nextcloud_password
fi

if has_component collabora; then
    ############################################################
    #### COLLABORA
    ./containers/25_configure_collabora.sh
fi

if [ "${USE_LXD_PROXY}" = "1" ]; then
    IFS=' ' read -r -a _extra_forwards <<< "${PORT_FORWARDS:-}"
    _extra_forwards+=("${HTTP_PORT}:rvprx:${HTTP_PORT}" "${HTTPS_PORT}:rvprx:${HTTPS_PORT}")
    for _map in "${_extra_forwards[@]}"; do
        IFS=':' read -r _host_port _ct _ct_port <<< "$_map"
        _ct_port=${_ct_port:-$_host_port}
        _var="IP_${_ct}"
        _ct_ip=$(eval echo "\${$_var}")
        if lxc info "${_ct}" >/dev/null 2>&1; then
            lxc config device add "${_ct}" "proxy${_host_port}" proxy listen="tcp:0.0.0.0:${_host_port}" connect="tcp:${_ct_ip}:${_ct_port}" >/dev/null 2>&1
        fi
    done
fi

################################################################################
