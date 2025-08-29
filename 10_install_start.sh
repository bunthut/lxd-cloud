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

# If vars file exist, source
if [ -f config/00_VARS ]; then
    source config/00_VARS

    # Override domains from environment variables when provided
    if [ -n "$FQDN_OVERRIDE" ]; then
        FQDN="$FQDN_OVERRIDE"
        sed -i "s/^FQDN=.*/FQDN=\"$FQDN\"/" config/00_VARS
    fi
    if [ -n "$FQDN_COLLABORA_OVERRIDE" ]; then
        FQDN_collabora="$FQDN_COLLABORA_OVERRIDE"
        sed -i "s/^FQDN_collabora=.*/FQDN_collabora=\"$FQDN_collabora\"/" config/00_VARS
    fi
    if [ -n "$FQDN_SMTP_OVERRIDE" ]; then
        FQDN_smtp="$FQDN_SMTP_OVERRIDE"
        sed -i "s/^FQDN_smtp=.*/FQDN_smtp=\"$FQDN_smtp\"/" config/00_VARS
    fi
    if [ -n "$HTTP_PORT_OVERRIDE" ]; then
        HTTP_PORT="$HTTP_PORT_OVERRIDE"
        sed -i "s/^HTTP_PORT=.*/HTTP_PORT=\"$HTTP_PORT\"/" config/00_VARS
    fi
    if [ -n "$HTTPS_PORT_OVERRIDE" ]; then
        HTTPS_PORT="$HTTPS_PORT_OVERRIDE"
        sed -i "s/^HTTPS_PORT=.*/HTTPS_PORT=\"$HTTPS_PORT\"/" config/00_VARS
    fi
    if [ -n "$COLLABORA_PORT_OVERRIDE" ]; then
        COLLABORA_PORT="$COLLABORA_PORT_OVERRIDE"
        sed -i "s/^COLLABORA_PORT=.*/COLLABORA_PORT=\"$COLLABORA_PORT\"/" config/00_VARS
    fi
else
    echo ""
    echo "$($_RED_)File « config/00_VARS » don't exist$($_WHITE_)"
    echo "$($_ORANGE_)Please reply to the next questions$($_WHITE_)"

    echo ""
    echo "$($_ORANGE_)** TECHNICAL **$($_WHITE_)"
    echo ""
    FQDN=${FQDN_OVERRIDE:-$FQDN}
    FQDN_collabora=${FQDN_COLLABORA_OVERRIDE:-$FQDN_collabora}
    FQDN_smtp=${FQDN_SMTP_OVERRIDE:-$FQDN_smtp}
    HTTP_PORT=${HTTP_PORT_OVERRIDE:-$HTTP_PORT}
    HTTPS_PORT=${HTTPS_PORT_OVERRIDE:-$HTTPS_PORT}
    COLLABORA_PORT=${COLLABORA_PORT_OVERRIDE:-$COLLABORA_PORT}
    read -p "$($_GREEN_)Internet network interface [$INTERNET_ETH]:$($_WHITE_) " input; INTERNET_ETH=${input:-$INTERNET_ETH}
    read -p "$($_GREEN_)FQDN [$FQDN]:$($_WHITE_) " input; FQDN=${input:-$FQDN}
    read -p "$($_GREEN_)Collabora FQDN [$FQDN_collabora]:$($_WHITE_) " input; FQDN_collabora=${input:-$FQDN_collabora}
    read -p "$($_GREEN_)SMTP FQDN [$FQDN_smtp]:$($_WHITE_) " input; FQDN_smtp=${input:-$FQDN_smtp}
    read -p "$($_GREEN_)HTTP port [$HTTP_PORT]:$($_WHITE_) " input; HTTP_PORT=${input:-$HTTP_PORT}
    read -p "$($_GREEN_)HTTPS port [$HTTPS_PORT]:$($_WHITE_) " input; HTTPS_PORT=${input:-$HTTPS_PORT}
    read -p "$($_GREEN_)Collabora port [$COLLABORA_PORT]:$($_WHITE_) " input; COLLABORA_PORT=${input:-$COLLABORA_PORT}
    read -p "$($_GREEN_)Technical Administrator Email [$TECH_ADMIN_EMAIL]:$($_WHITE_) " input; TECH_ADMIN_EMAIL=${input:-$TECH_ADMIN_EMAIL}

    echo ""
    echo "$($_ORANGE_)** CLOUD **$($_WHITE_)"
    echo ""
    read -p "$($_GREEN_)Nextcloud Administrator User [$NEXTCLOUD_admin_user]:$($_WHITE_) " input; NEXTCLOUD_admin_user=${input:-$NEXTCLOUD_admin_user}
    read -p "$($_GREEN_)Nextcloud Administrator Email [$NEXTCLOUD_admin_email]:$($_WHITE_) " input; NEXTCLOUD_admin_email=${input:-$NEXTCLOUD_admin_email}
    read -p "$($_GREEN_)Nextcloud Administrator Password (hidden entry):$($_WHITE_) " -rs input; NEXTCLOUD_admin_password=${input:-$NEXTCLOUD_admin_password}

    cat << EOF > config/00_VARS
INTERNET_ETH="$INTERNET_ETH"
FQDN="$FQDN"
FQDN_collabora="$FQDN_collabora"
FQDN_smtp="$FQDN_smtp"
HTTP_PORT="$HTTP_PORT"
HTTPS_PORT="$HTTPS_PORT"
COLLABORA_PORT="$COLLABORA_PORT"
TECH_ADMIN_EMAIL="$TECH_ADMIN_EMAIL"
NEXTCLOUD_admin_user="$NEXTCLOUD_admin_user"
NEXTCLOUD_admin_email="$NEXTCLOUD_admin_email"
NEXTCLOUD_admin_password="$NEXTCLOUD_admin_password"
EOF

    echo ""
    echo "$($_ORANGE_)File « config/00_VARS » generated$($_WHITE_)"
    echo ""

fi

# Load Network Vars
source config/01_NETWORK_VARS

# Load Other vars 
# - DEBIAN_RELEASE
source config/03_OTHER_VARS

################################################################################
#### HOST CONFIGURATION

#############
echo "$($_ORANGE_)Update and Upgrade system packages and default apt configuration$($_WHITE_)"

# Allow overriding the Python package version; default to python3
PYTHON_PACKAGE=${PYTHON_PACKAGE:-python3}


PACKAGES="vim apt-utils bsd-mailx unattended-upgrades apt-listchanges bind9-host logrotate logwatch postfix git fail2ban ${PYTHON_PACKAGE} python-is-python3"




apt-get update > /dev/null
DEBIAN_FRONTEND=noninteractive apt-get -y install $PACKAGES > /dev/null
DEBIAN_FRONTEND=noninteractive apt-get -y upgrade > /dev/null
git config --global user.name "$HOSTNAME"
git config --global user.email "root@$HOSTNAME"

# Configure unattended upgrades and notifications
sed -E -i "s|^(//\s*)?Unattended-Upgrade::Mail.*|Unattended-Upgrade::Mail \"$TECH_ADMIN_EMAIL\";|" /etc/apt/apt.conf.d/50unattended-upgrades
sed -E -i 's|^(//\s*)?Unattended-Upgrade::Automatic-Reboot.*|Unattended-Upgrade::Automatic-Reboot "true";|' /etc/apt/apt.conf.d/50unattended-upgrades
cat << EOF > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
sed -E -i "s|^email_address=.*|email_address=$TECH_ADMIN_EMAIL|" /etc/apt/listchanges.conf
sed -E -i 's|^which=.*|which=news|' /etc/apt/listchanges.conf

# Basic Debian configuration
# Configure system mail alias for root
echo "root: $TECH_ADMIN_EMAIL" >> /etc/aliases
newaliases > /dev/null

# Configure git defaults
git config --global user.name "$HOSTNAME"
git config --global user.email "root@$HOSTNAME"

# Configure fail2ban with email notifications
cat << EOF > /etc/fail2ban/jail.local
[DEFAULT]
destemail = $TECH_ADMIN_EMAIL
sender = root@$HOSTNAME

[sshd]
enabled = true
EOF
systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban >/dev/null 2>&1

# Configure logwatch daily report
cat << EOF > /etc/cron.daily/00logwatch
#!/bin/bash
logwatch --output mail --mailto "$TECH_ADMIN_EMAIL"
EOF
chmod +x /etc/cron.daily/00logwatch

# Configure unattended upgrades notifications
cat << EOF > /etc/apt/apt.conf.d/51unattended-upgrades-local
Unattended-Upgrade::Mail "$TECH_ADMIN_EMAIL";
EOF

#############

if [ -n "$SKIP_DNS_CHECK" ]; then
    echo "$($_ORANGE_)Skipping DNS record validation$($_WHITE_)"
else
    echo "$($_ORANGE_)Test if FQDN records A and PTR is OK$($_WHITE_)"
    TEST_IP=$(host -t A $FQDN|awk '{print $4}')
    TEST_FQDN=$(host -t PTR $TEST_IP|awk '{print $5}')
    # Remove « . » in end on PTR record
    if [ "${TEST_FQDN::-1}" != "$FQDN" ] ; then
        echo "$($_RED_)"
        echo "ERROR DNS RECORDS"
        echo "Your FQDN « $FQDN » is not equal to PTR value: « $TEST_FQDN »"
        echo "Please fix that and retry"
        echo "$($_WHITE_)"
        exit 1
    else
        echo "$($_GREEN_)FQDN records A and PTR is OK$($_WHITE_)"
    fi
fi

#############

# Postfix conf file
cat << EOF > /etc/postfix/main.cf
mydomain = $FQDN
myorigin = \$mydomain
smtpd_banner = \$myhostname ESMTP \$mail_name (Debian/GNU)
biff = no
append_dot_mydomain = no
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
mydestination = \$myhostname, localhost.\$mydomain, localhost
relayhost = $IP_smtp_PRIV
inet_interfaces = loopback-only
recipient_delimiter = +
inet_protocols = ipv4
EOF

# Send crontab return to admin (TECH_ADMIN_EMAIL)
sed -i "1s/^/# Send cron report to admin\nMAILTO='$TECH_ADMIN_EMAIL'\n\n/" /etc/crontab

# Configure fail2ban
echo "$($_ORANGE_)Configure: fail2ban$($_WHITE_)"
cat << EOF > /etc/fail2ban/jail.local
[DEFAULT]
destemail = "$TECH_ADMIN_EMAIL"

[sshd]
enabled = true
EOF
systemctl enable --now fail2ban > /dev/null

# Build list of port forward mappings
IFS=' ' read -r -a _extra_forwards <<< "${PORT_FORWARDS:-}"
_default_forwards=("${HTTP_PORT}:rvprx:${HTTP_PORT}" "${HTTPS_PORT}:rvprx:${HTTPS_PORT}")
PORT_FORWARD_LIST=("${_default_forwards[@]}" "${_extra_forwards[@]}")

if [ "${USE_LXD_PROXY}" = "1" ]; then
    echo "$($_ORANGE_)Skipping iptables setup; will configure LXD proxy devices$($_WHITE_)"
else
    # Enable Masquerade and NAT rules
    echo "$($_ORANGE_)Install: iptables-persistent$($_WHITE_)"
    DEBIAN_FRONTEND=noninteractive apt-get -y install iptables-persistent > /dev/null
    echo "$($_ORANGE_)Enable Masquerade and NAT rules$($_WHITE_)"
    cat <<EOF > /etc/iptables/rules.v4
################################################################################
##########                          TABLE NAT                         ##########
################################################################################
*nat
####
:PREROUTING ACCEPT [0:0]
# Custom chain for WAN prerouting
:zone_wan_PREROUTING - [0:0]
-A PREROUTING -i $INTERNET_ETH -j zone_wan_PREROUTING -m comment --comment "Internet Input PREROUTING"
EOF
    for _map in "${PORT_FORWARD_LIST[@]}"; do
        IFS=':' read -r _host_port _ct _ct_port <<< "$_map"
        _ct_port=${_ct_port:-$_host_port}
        _var="IP_${_ct}"
        _ct_ip=$(eval echo "\${$_var}")
        if [ -n "$_ct_ip" ]; then
            echo "# NAT ${_host_port} > ${_ct}" >> /etc/iptables/rules.v4
            echo "-A zone_wan_PREROUTING -p tcp -m tcp --dport ${_host_port} -j DNAT --to-destination ${_ct_ip}:${_ct_port} -m comment --comment \"Routing port ${_host_port} > ${_ct} - TCP\"" >> /etc/iptables/rules.v4
        fi
    done
    cat <<EOF >> /etc/iptables/rules.v4
COMMIT
EOF
    iptables-restore /etc/iptables/rules.v4
fi

##### DEBIAN
if [ "$LXD_STORAGE_DRIVER" = "zfs" ]; then
    echo "$($_ORANGE_)Install: snapd, udev and zfs$($_WHITE_)"
    DEBIAN_FRONTEND=noninteractive apt-get -y install snapd udev zfsutils-linux > /dev/null
else
    echo "$($_ORANGE_)Install: snapd, udev and btrfs$($_WHITE_)"
    DEBIAN_FRONTEND=noninteractive apt-get -y install snapd udev btrfs-progs > /dev/null
fi
DEBIAN_FRONTEND=noninteractive apt-get clean

echo "$($_ORANGE_)Install: LXD with snap$($_WHITE_)"
if snap list | grep -q '^lxd\s'; then
    echo "$($_ORANGE_)LXD snap already installed, skipping$($_WHITE_)"
else
    snap install lxd --channel="$LXD_SNAP_CHANNEL"
fi

##### UBUNTU
## Install LXD package
#apt-get install lxd-client/trusty-backports
#apt-get install lxd/trusty-backports
##apt-get install lxd

echo "$($_GREEN_)LXD is installed$($_WHITE_)"
echo ""
echo "$($_RED_)Please logout/login in bash to prevent snap bug and start script :$($_WHITE_)"
echo "$($_GREEN_)11_install_next.sh$($_WHITE_)"

# Test if /run/reboot-required file exist, and print warning
if [ -f /run/reboot-required ] ; then
    echo "$($_RED_)!! WARNING !!$($_WHITE_)"
    echo "$($_RED_)/run/reboot-required exist, you need to reboot this node before next step$($_WHITE_)"
fi
