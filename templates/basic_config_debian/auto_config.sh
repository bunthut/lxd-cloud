#!/bin/bash
set -e

# Local version of basic Debian configuration script
# This script reads configuration variables from
# /srv/git/basic_config_debian/conf if present and applies
# a minimal set of system defaults.

CONF_DIR="/srv/git/basic_config_debian"
CONF_FILE="$CONF_DIR/conf"

if [ -f "$CONF_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONF_FILE"
fi

# Configure git defaults when provided
if [ -n "$GIT_USERNAME" ]; then
    git config --global user.name "$GIT_USERNAME"
fi

if [ -n "$GIT_EMAIL" ]; then
    git config --global user.email "$GIT_EMAIL"
fi

# Configure unattended-upgrades email notifications
if [ -n "$UNATTENDED_EMAIL" ]; then
    sed -E -i "s|^(//\s*)?Unattended-Upgrade::Mail.*|Unattended-Upgrade::Mail \"$UNATTENDED_EMAIL\";|" /etc/apt/apt.conf.d/50unattended-upgrades
    cat <<EOF > /etc/apt/apt.conf.d/51unattended-upgrades-local
Unattended-Upgrade::Mail "$UNATTENDED_EMAIL";
EOF
    echo "root: $UNATTENDED_EMAIL" >> /etc/aliases
    newaliases >/dev/null 2>&1 || true
fi

exit 0

