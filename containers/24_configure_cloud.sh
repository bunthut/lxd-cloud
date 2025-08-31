#!/bin/bash
set -e

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

# Path of git repository
# ../
GIT_PATH="$(realpath ${0%/*/*})"

# Load Vars
source $GIT_PATH/config/00_VARS

# Load Network Vars
source $GIT_PATH/config/01_NETWORK_VARS

# Load Resources Vars
source $GIT_PATH/config/02_RESOURCES_VARS

# Load Other vars 
# - MAX_UPLOAD_FILE_SIZE
# - LANGUAGE
# - TIME_ZONE
# - NEXTCLOUD_LOG_ROTATE_SIZE
# - NEXTCLOUD_DATA_DIR
source $GIT_PATH/config/03_OTHER_VARS

################################################################################

lxc_exec() {
    if ! lxc exec cloud -- "$@"; then
        echo "$($_RED_)Failed: lxc exec cloud -- $*$($_WHITE_)" >&2
        exit 1
    fi
}

#### CLOUD

# Test if Nextcloud database password is set
if [ ! -f /tmp/lxc_nextcloud_password ] ; then
    echo "$($_RED_)You need to create « /tmp/lxc_nextcloud_password » with nextcloud user passord$($_WHITE_)"
    exit 1
fi
MDP_nextcoud="$(cat /tmp/lxc_nextcloud_password)"

# Ensure cloud container exists and is running
if ! lxc info cloud --state >/dev/null 2>&1; then
    echo "$($_RED_)Cloud container not found$($_WHITE_)"
    exit 1
fi

CLOUD_STATE=$(lxc info cloud --state 2>/dev/null | awk -F': ' '/Status:/ {print $2}')
if [ "$CLOUD_STATE" != "Running" ]; then
    echo "$($_ORANGE_)Starting cloud container$($_WHITE_)"
    if ! lxc start cloud; then
        echo "$($_RED_)Unable to start cloud container$($_WHITE_)"
        exit 1
    fi
    CLOUD_STATE=$(lxc info cloud --state 2>/dev/null | awk -F': ' '/Status:/ {print $2}')
    if [ "$CLOUD_STATE" != "Running" ]; then
        echo "$($_RED_)Cloud container is not running$($_WHITE_)"
        exit 1
    fi
fi

echo "$($_GREEN_)BEGIN cloud$($_WHITE_)"

echo "$($_ORANGE_)Create symlinks for /etc/nginx and /etc/letsencrypt to /srv/lxd$($_WHITE_)"
lxc_exec ln -s /srv/lxd/var/www/ /var/

echo "$($_ORANGE_)Create and attach data cloud ($NEXTCLOUD_DATA_DIR) directory$($_WHITE_)"
mkdir -p $NEXTCLOUD_DATA_DIR
chown 1000033:1000033 $NEXTCLOUD_DATA_DIR
lxc config device add cloud DataCloud disk path=$NEXTCLOUD_DATA_DIR source=$NEXTCLOUD_DATA_DIR

echo "$($_ORANGE_)Create « occ » alias command$($_WHITE_)"
lxc_exec bash -c 'echo "sudo -u www-data php /var/www/nextcloud/occ \$@" > /usr/local/bin/occ
                           chmod +x /usr/local/bin/occ
                           '

echo "$($_ORANGE_)Install packages for nextcloud...$($_WHITE_)"
lxc_exec bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install \
    wget            \
    curl            \
    sudo            \
    apache2         \
    mariadb-client  \
    redis-server    \
"
# LXD Version (with snap)
# see https://linuxcontainers.org/lxd/news/
# 2.0 (11/04/2016) with a 5 years support commitment from upstream, ending on 1st of June 2021
# 3.0 (02/04/2018) will be supported until June 2023
LXD_VERSION="5.0/stable"

# LXD snap channel
# see https://snapcraft.io/lxd for available channels
LXD_SNAP_CHANNEL="latest/stable"



echo "$($_ORANGE_)apache2 FIX ServerName$($_WHITE_)"
lxc_exec bash -c "echo 'ServerName $FQDN' > /etc/apache2/conf-available/99_ServerName.conf
                           a2enconf 99_ServerName > /dev/null"
echo "$($_ORANGE_)Enable php-fpm in apache2$($_WHITE_)"
lxc_exec bash -c "a2enmod proxy_fcgi setenvif > /dev/null
                           a2enconf php8.2-fpm > /dev/null"

echo "$($_ORANGE_)Enable apache2 mods$($_WHITE_)"
lxc_exec bash -c "a2enmod rewrite > /dev/null
                           a2enmod headers env dir mime remoteip > /dev/null"

echo "$($_ORANGE_)Tuning opcache (php) conf$($_WHITE_)"
lxc_exec bash -c "sed -i                                                                              \
    -e 's/;opcache.enable=0/opcache.enable=1/'                                      \
    -e 's/;opcache.enable_cli=0/opcache.enable_cli=1/'                              \
    -e 's/;opcache.interned_strings_buffer=4/opcache.interned_strings_buffer=8/'    \
    -e 's/;opcache.max_accelerated_files=2000/opcache.max_accelerated_files=10000/' \
    -e 's/;opcache.memory_consumption=64/opcache.memory_consumption=128/'           \
    -e 's/;opcache.save_comments=1/opcache.save_comments=1/'                        \
    -e 's/;opcache.revalidate_freq=2/opcache.revalidate_freq=1/'                    \
    /etc/php/8.*/fpm/php.ini"


echo "$($_ORANGE_)Restart FPM$($_WHITE_)"
lxc_exec bash -c "systemctl restart php8.2-fpm.service"

echo "$($_ORANGE_)Restart apache2$($_WHITE_)"
lxc_exec bash -c "systemctl restart apache2.service"

echo "$($_ORANGE_)Test Apache + PHP with FPM$($_WHITE_)"
lxc_exec bash -c "cat << EOF > /var/www/html/phpinfo.php
<?php
phpinfo();
EOF"

lxc_exec bash -c 'if curl -s 127.0.0.1/phpinfo.php|grep -q php-fpm; then
    echo -e "\n\033[32m ** FPM OK **\033[00m\n"
else
    >&2 echo -e "\033[31m==================== ERROR  ====================\033[00m"
    >&2 echo -e "\033[31m==================== FPM HS ====================\033[00m"
    exit 1
fi'

lxc_exec bash -c "rm -f /var/www/html/phpinfo.php"

echo "$($_ORANGE_)apache2 listen only in Private IP$($_WHITE_)"
lxc_exec bash -c "echo 'Listen $IP_cloud_PRIV:80' > /etc/apache2/ports.conf"

echo "$($_ORANGE_)Download and uncompress Nextcloud$($_WHITE_)"
lxc_exec bash -c "wget -q $NEXTCLOUD_URL -O /tmp/nextcloud.tar.bz2"
lxc_exec bash -c "tar xaf /tmp/nextcloud.tar.bz2 -C /var/www/"
lxc_exec bash -c "rm -f /tmp/nextcloud.tar.bz2"

echo "$($_ORANGE_)Update directory privileges$($_WHITE_)"
lxc_exec bash -c "
    chown -R www-data:www-data /var/www/nextcloud/
    mkdir -p /var/log/nextcloud
    chown -R www-data:www-data /var/log/nextcloud
    "

echo "$($_ORANGE_)Create Vhost apache for Nextcloud$($_WHITE_)"
lxc_exec bash -c 'cat << "EOF" > /etc/apache2/sites-available/nextcloud.conf
<VirtualHost *:80>
    ServerName __FQDN__

    ServerAdmin __MAIL_ADMIN__
    DocumentRoot /var/www/nextcloud

    # Autorisation des réécritures
    RewriteEngine  on

    # Tunning des logs de sortie
    LogFormat "%h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\" \"%{Host}i\"" MyFormat
    CustomLog ${APACHE_LOG_DIR}/cloud_access.log MyFormat

</VirtualHost>

<Directory /var/www/nextcloud>

    Options +FollowSymLinks
    AllowOverride All
    Require all granted

    <IfModule mod_dav.c>
        Dav off
    </IfModule>

    SetEnv HOME /var/www/nextcloud
    SetEnv HTTP_HOME /var/www/nextcloud

</Directory>
EOF'

echo "$($_ORANGE_)Update FQDN$($_WHITE_)"
lxc_exec bash -c "sed -i -e 's/__FQDN__/$FQDN/' -e 's/__MAIL_ADMIN__/$TECH_ADMIN_EMAIL/' /etc/apache2/sites-available/nextcloud.conf"

echo "$($_ORANGE_)Disable Default Vhost and enable nextcloud$($_WHITE_)"
lxc_exec bash -c "a2dissite 000-default > /dev/null
                           a2ensite nextcloud.conf > /dev/null"

echo "$($_ORANGE_)apache2 configtest$($_WHITE_)"
lxc_exec bash -c "apache2ctl configtest"

echo "$($_ORANGE_)Reload apache2$($_WHITE_)"
lxc_exec bash -c "systemctl reload apache2"

echo "$($_ORANGE_)Nextcloud installation$($_WHITE_)"
if lxc exec cloud -- bash -c '[ -f /var/www/nextcloud/config/config.php ] || occ status >/dev/null 2>&1'; then
    echo "$($_GREEN_)Existing Nextcloud installation detected - reusing instance$($_WHITE_)"
else
    lxc_exec bash -c "occ maintenance:install --database 'mysql' --database-host '$IP_mariadb_PRIV' --database-name 'nextcloud'  --database-user 'nextcloud' --database-pass '$MDP_nextcoud' --admin-user '$NEXTCLOUD_admin_user' --admin-pass '$NEXTCLOUD_admin_password' --data-dir='$NEXTCLOUD_DATA_DIR'"
fi

echo "$($_ORANGE_)Tune MAX upload file size$($_WHITE_)"
lxc_exec bash -c "sed -i \
                             -e 's/upload_max_filesize=.*/upload_max_filesize=$MAX_UPLOAD_FILE_SIZE/' \
                             -e 's/post_max_size=.*/post_max_size=$MAX_UPLOAD_FILE_SIZE/' \
                             /var/www/nextcloud/.user.ini
                           "

echo "$($_ORANGE_)Tune Nextcloud conf$($_WHITE_)"
lxc_exec bash -c "occ config:system:set trusted_domains 0    --value='$FQDN'
                           occ config:system:set overwrite.cli.url    --value='$FQDN'
                           occ config:system:set htaccess.RewriteBase --value='/'
                           # Language and time zone settings
                           occ config:system:set default_language     --value='$LANGUAGE'
                           occ config:system:set force_language       --value='$LANGUAGE'
                           occ config:system:set logtimezone          --value='$TIME_ZONE'
                           # Redis
                           occ config:system:set memcache.local       --value='\\OC\\Memcache\\Redis'
                           occ config:system:set memcache.locking     --value='\\OC\\Memcache\\Redis'
                           occ config:system:set redis host           --value='localhost'
                           occ config:system:set redis port           --value='6379'
                           # Log
                           occ config:system:set loglevel             --value='2'
                           occ config:system:set logfile              --value='/var/log/nextcloud/nextcloud.log'
                           # Example for 100MB :
                           # 100MB ( 100 * 1024 * 1024 ) = 104857600 byte
                           occ config:system:set log_rotate_size      --value=$(( $NEXTCLOUD_LOG_ROTATE_SIZE * 1024 * 1024 ))
                           "

echo "$($_ORANGE_)Update .htaccess$($_WHITE_)"
lxc_exec bash -c "occ maintenance:update:htaccess > /dev/null"

echo "$($_ORANGE_)Install applications in Nextcloud$($_WHITE_)"
lxc_exec bash -c "
    occ app:install calendar
    occ app:enable  calendar
    occ app:enable  admin_audit
    occ app:install contacts
    occ app:enable  contacts
    occ app:install announcementcenter
    occ app:enable  announcementcenter
    # Collabora Online
    occ app:install richdocuments
    occ app:enable  richdocuments
    occ app:install quota_warning
    occ app:enable  quota_warning
    occ app:install files_rightclick
    occ app:enable  files_rightclick
    occ app:enable  files_pdfviewer
    # Talk
    occ app:install spreed
    occ app:enable  spreed
    # Registration - WARNING: need to sed admin_approval_required to true !
    occ app:install registration
    occ app:enable registration
"

echo "$($_ORANGE_)Enable admin_approval_required for registration app$($_WHITE_)"
lxc_exec bash -c "
    occ config:app:set registration admin_approval_required --value='yes'
"

echo "$($_ORANGE_)Enable quota warning notification$($_WHITE_)"
lxc_exec bash -c "occ config:app:set quota_warning info_email    --value='yes'
                           occ config:app:set quota_warning warning_email --value='yes'
                           occ config:app:set quota_warning alert_email   --value='yes'
                           "

echo "$($_ORANGE_)Configure SMTP in Nextcloud$($_WHITE_)"
lxc_exec bash -c "occ config:system:set mail_smtpmode --value='smtp'
                           occ config:system:set mail_smtpauthtype --value='LOGIN'
                           occ config:system:set mail_from_address --value='cloud'
                           occ config:system:set mail_domain --value='$FQDN'
                           occ config:system:set mail_smtphost --value='$IP_smtp_PRIV'
                           occ config:system:set mail_smtpport --value='25'
                           "

echo "$($_ORANGE_)Set Collabora Online trusted domain$($_WHITE_)"
lxc_exec bash -c "occ config:app:set richdocuments wopi_url --value='https://$FQDN_collabora'"

echo "$($_ORANGE_)Set email in Nextcloud admin account$($_WHITE_)"
lxc_exec bash -c "occ user:setting $NEXTCLOUD_admin_user settings email '$NEXTCLOUD_admin_email'"

echo "$($_ORANGE_)Set transparency client ip for Nextcloud and Apache$($_WHITE_)"
lxc_exec bash -c "
                           occ config:system:set trusted_proxies 0 --value='$IP_rvprx_PRIV'
                           occ config:system:set forwarded_for_headers 0 --value='HTTP_X_FORWARDED_FOR'
                           cat << EOF > /etc/apache2/mods-available/remoteip.conf
RemoteIPHeader X-Forwarded-For
RemoteIPTrustedProxy $IP_rvprx_PRIV
EOF
                           "

################################################################################

#echo "$($_ORANGE_)Add Let's Encrypt chain.pem (CA Root Certificates) in Nextcloud$($_WHITE_)"
#chain_pem="$(lxc exec rvprx -- cat /etc/letsencrypt/live/$FQDN/chain.pem)"
#lxc exec cloud -- bash -c "cat << 'EOF' >> /var/www/nextcloud/resources/config/ca-bundle.crt
#
#Let's Encrypt
#=============
#$chain_pem
#EOF
#"

echo "$($_ORANGE_)Clean package cache (.deb files)$($_WHITE_)"
lxc_exec bash -c "apt-get clean"

echo "$($_ORANGE_)Reboot container to free memory$($_WHITE_)"
lxc restart cloud --force

echo "$($_ORANGE_)Set CPU and Memory limits$($_WHITE_)"
lxc profile add cloud $LXC_PROFILE_cloud_CPU
lxc profile add cloud $LXC_PROFILE_cloud_MEM

echo "$($_GREEN_)END cloud$($_WHITE_)"
echo ""

