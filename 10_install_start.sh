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
else
    echo ""
    echo "$($_RED_)File « config/00_VARS » don't exist$($_WHITE_)"
    echo "$($_ORANGE_)Please reply to the next questions$($_WHITE_)"

    echo ""
    echo "$($_ORANGE_)** TECHNICAL **$($_WHITE_)"
    echo ""
    echo -n "$($_GREEN_)Internet network interface:$($_WHITE_) "
    read INTERNET_ETH
    echo -n "$($_GREEN_)FQDN:$($_WHITE_) "
    read FQDN
    echo -n "$($_GREEN_)Collabora FQDN:$($_WHITE_) "
    read FQDN_collabora
    echo -n "$($_GREEN_)Technical Administrator Email:$($_WHITE_) "
    read TECH_ADMIN_EMAIL

    echo ""
    echo "$($_ORANGE_)** CLOUD **$($_WHITE_)"
    echo ""
    echo -n "$($_GREEN_)Nextcloud Administrator User:$($_WHITE_) "
    read NEXTCLOUD_admin_user
    echo -n "$($_GREEN_)Nextcloud Administrator Email:$($_WHITE_) "
    read NEXTCLOUD_admin_email
    echo -n "$($_GREEN_)Nextcloud Administrator Password (hidden entry):$($_WHITE_) "
    read -rs NEXTCLOUD_admin_password

    cat << EOF > config/00_VARS
INTERNET_ETH="$INTERNET_ETH"
FQDN="$FQDN"
FQDN_collabora="$FQDN_collabora"
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

PACKAGES="vim apt-utils bsd-mailx unattended-upgrades apt-listchanges bind9-host logrotate postfix python3.12 python-is-python3"


apt-get update > /dev/null
DEBIAN_FRONTEND=noninteractive apt-get -y install $PACKAGES > /dev/null
DEBIAN_FRONTEND=noninteractive apt-get -y upgrade > /dev/null

# Basic Debian configuration
mkdir -p /srv/git
git clone https://github.com/AlbanVidal/basic_config_debian.git /srv/git/basic_config_debian
# Setup config file for auto configuration
>                                              /srv/git/basic_config_debian/conf
echo "UNATTENDED_EMAIL='$TECH_ADMIN_EMAIL'" >> /srv/git/basic_config_debian/conf
echo "GIT_USERNAME='$HOSTNAME'"             >> /srv/git/basic_config_debian/conf
echo "GIT_EMAIL='root@$HOSTNAME'"           >> /srv/git/basic_config_debian/conf
echo "SSH_EMAIL_ALERT='$TECH_ADMIN_EMAIL'"  >> /srv/git/basic_config_debian/conf
# Launch auto configuration script
/srv/git/basic_config_debian/auto_config.sh

#############

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

# Nat post 80 and 443 => RVPRX
# Enable Masquerade and NAT rules
echo "$($_ORANGE_)Install: iptables-persistent$($_WHITE_)"
DEBIAN_FRONTEND=noninteractive apt-get -y install iptables-persistent > /dev/null
echo "$($_ORANGE_)Enable Masquerade and NAT rules$($_WHITE_)"
cat << EOF > /etc/iptables/rules.v4
################################################################################
##########                          TABLE NAT                         ########## 
################################################################################
*nat
####
:PREROUTING ACCEPT [0:0]
# Internet Input (PREROUTING)
-N zone_wan_PREROUTING
-A PREROUTING -i $INTERNET_ETH -j zone_wan_PREROUTING -m comment --comment "Internet Input PREROUTING"
# NAT 80 > RVPRX (nginx)
-A zone_wan_PREROUTING -p tcp -m tcp --dport 80 -j DNAT --to-destination $IP_rvprx:80 -m comment --comment "Routing port 80 > RVPRX - TCP"
# NAT 443 > RVPRX (nginx)
-A zone_wan_PREROUTING -p tcp -m tcp --dport 443 -j DNAT --to-destination $IP_rvprx:443 -m comment --comment "Routing port 443 > RVPRX - TCP"
COMMIT
EOF
iptables-restore /etc/iptables/rules.v4

##### DEBIAN
echo "$($_ORANGE_)Install: snapd, udev, btrfs and lvm$($_WHITE_)"
DEBIAN_FRONTEND=noninteractive apt-get -y install snapd udev btrfs-tools lvm2 thin-provisioning-tools > /dev/null
DEBIAN_FRONTEND=noninteractive apt-get clean

echo "$($_ORANGE_)Install: LXD with snap$($_WHITE_)"
snap install lxd --channel="$LXD_VERSION"

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
