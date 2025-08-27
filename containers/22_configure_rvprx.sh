#!/bin/bash

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
# - DEBIAN_RELEASE
# - CREATE_CERTIFICATES
source $GIT_PATH/config/03_OTHER_VARS

################################################################################

#### RVPRX
echo "$($_GREEN_)BEGIN rvprx$($_WHITE_)"

echo "$($_ORANGE_)Create symlinks for /etc/nginx and /etc/letsencrypt to /srv/lxd$($_WHITE_)"
lxc exec rvprx -- ln -s /srv/lxd/etc/nginx /etc/
lxc exec rvprx -- ln -s /srv/lxd/etc/letsencrypt /etc/

echo "$($_ORANGE_)Install specific packages$($_WHITE_)"
# Nginx - fail2ban
#lxc exec rvprx -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install nginx iptables fail2ban > /dev/null"
lxc exec rvprx -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install nginx iptables > /dev/null"

# Certbot for Nginx
lxc exec rvprx -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install certbot python3-certbot-nginx > /dev/null"


# conf file letsencrypt
cat << EOF > /tmp_lxd_rvprx_etc_letsencrypt_cli.ini
# Because we are using logrotate for greater flexibility, disable the
# internal certbot logrotation.
max-log-backups = 0
# Change size of Key
rsa-key-size = 4096
EOF
lxc file push /tmp_lxd_rvprx_etc_letsencrypt_cli.ini rvprx/etc/letsencrypt/cli.ini

# Generating certificates
echo "$($_ORANGE_)Generating certificates: $FQDN$($_WHITE_)"
if $CREATE_CERTIFICATES ; then
    lxc exec rvprx -- bash -c "certbot certonly -n --agree-tos --email $TECH_ADMIN_EMAIL --nginx -d $FQDN,$FQDN_collabora > /dev/null"
else
    echo "$($_GREEN_)CREATE_CERTIFICATES=true, don't create certificates, you need to setup it manually$($_WHITE_)"
fi

## RVPRX dhparam
#echo "$($_ORANGE_)Generating dhparam$($_WHITE_)"
#lxc exec rvprx -- bash -c "openssl dhparam -out /etc/nginx/dhparam.pem 2048"

echo "$($_ORANGE_)Nginx: Conf, Vhosts and tuning$($_WHITE_)"
lxc file push $GIT_PATH/templates/rvprx/etc_nginx_RVPRX_common.conf rvprx/etc/nginx/RVPRX_common.conf

# RVPRX vhosts
cat << EOF > /tmp_lxd_rvprx_etc_nginx_rvprx-cloud
server {
    listen      80;
    server_name $FQDN;
    return 301  https://$FQDN\$request_uri;
}

server {
    listen      443 ssl http2;
    server_name $FQDN;

    # Let's Encrypt:
    ssl_certificate     /etc/letsencrypt/live/$FQDN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$FQDN/privkey.pem;

    # Add common Conf:
    include /etc/nginx/RVPRX_common.conf;

    # LOGS
    gzip on;
    access_log /var/log/nginx/cloud_access.log;
    error_log  /var/log/nginx/cloud_error.log;

    location / { proxy_pass http://$IP_cloud_PRIV/; }
}
EOF
lxc file push /tmp_lxd_rvprx_etc_nginx_rvprx-cloud rvprx/etc/nginx/sites-available/rvprx-cloud

cat << EOF > /tmp_lxd_rvprx_etc_nginx_rvprx-collabora
server {
    listen      80;
    server_name $FQDN_collabora;
    return 301  https://$FQDN_collabora\$request_uri;
}

server {
    listen      443 ssl http2;
    server_name $FQDN_collabora;

    # Let's Encrypt:
    ssl_certificate     /etc/letsencrypt/live/$FQDN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$FQDN/privkey.pem;

    # Add common Conf:
    include /etc/nginx/RVPRX_common.conf;

    # LOGS
    gzip on;
    access_log /var/log/nginx/collabora_access.log;
    error_log  /var/log/nginx/collabora_error.log;

    # static files
    location ^~ /loleaflet {
        proxy_pass https://$IP_collabora_PRIV:9980;
        proxy_set_header Host \$http_host;
    }

    # WOPI discovery URL
    location ^~ /hosting/discovery {
        proxy_pass https://$IP_collabora_PRIV:9980;
        proxy_set_header Host \$http_host;
    }

   # main websocket
   location ~ ^/lool/(.*)/ws$ {
       proxy_pass https://$IP_collabora_PRIV:9980;
       proxy_set_header Upgrade \$http_upgrade;
       proxy_set_header Connection "Upgrade";
       proxy_set_header Host \$http_host;
       proxy_read_timeout 36000s;
   }
   
   # download, presentation and image upload
   location ~ ^/lool {
       proxy_pass https://$IP_collabora_PRIV:9980;
       proxy_set_header Host \$http_host;
   }
   
   # Admin Console websocket
   location ^~ /lool/adminws {
       proxy_pass https://$IP_collabora_PRIV:9980;
       proxy_set_header Upgrade \$http_upgrade;
       proxy_set_header Connection "Upgrade";
       proxy_set_header Host \$http_host;
       proxy_read_timeout 36000s;
   }

   # The others URLs are redirected to cloud
   location / {
       return 301  https://$FQDN;
   }

}
EOF
lxc file push /tmp_lxd_rvprx_etc_nginx_rvprx-collabora rvprx/etc/nginx/sites-available/rvprx-collabora

# Disable « default » vhost and enable new
lxc exec rvprx -- bash -c "rm -f /etc/nginx/sites-enabled/default"
lxc exec rvprx -- bash -c "ln -s /etc/nginx/sites-available/rvprx-cloud /etc/nginx/sites-enabled/"
lxc exec rvprx -- bash -c "ln -s /etc/nginx/sites-available/rvprx-collabora /etc/nginx/sites-enabled/"

# Fix server_names_hash_bucket_size
lxc exec rvprx -- bash -c "sed -i 's/# server_names_hash_bucket_size.*/server_names_hash_bucket_size 64;/' /etc/nginx/nginx.conf"

# Set max file size to « $MAX_UPLOAD_FILE_SIZE » (editable in ../config/03_OTHER_VARS)
lxc exec rvprx -- bash -c "sed -i '/http {/a \\\t# Set max file size to $MAX_UPLOAD_FILE_SIZE\\n\\tclient_max_body_size $MAX_UPLOAD_FILE_SIZE;' /etc/nginx/nginx.conf |grep -C2 body_size"

# Test nginx conf and reload
lxc exec rvprx -- nginx -t
lxc exec rvprx -- nginx -s reload

# Disable certbot renew, already exists => /etc/cron.d/certbot
## Cron renew Let's encrypt certificate
#echo "$($_ORANGE_)Create renew Let's encrypt certificate daily cron$($_WHITE_)"
#lxc exec rvprx -- bash -c "cat << EOF > /etc/cron.daily/certbot-renew
##!/bin/bash
#
#certbot renew --nginx > /dev/null
#EOF"
 
################################################################################

echo "$($_ORANGE_)Clean package cache (.deb files)$($_WHITE_)"
lxc exec rvprx -- bash -c "apt-get clean"

echo "$($_ORANGE_)Reboot container to free memory$($_WHITE_)"
lxc restart rvprx --force

echo "$($_ORANGE_)Set CPU and Memory limits$($_WHITE_)"
lxc profile add rvprx $LXC_PROFILE_rvprx_CPU
lxc profile add rvprx $LXC_PROFILE_rvprx_MEM

echo "$($_GREEN_)END rvprx$($_WHITE_)"
echo ""

