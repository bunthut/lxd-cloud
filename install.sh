#!/bin/bash
set -e

show_help() {
    cat <<USAGE
Usage: $0 [OPTIONS]

Options:
  --all                     Install all components
  --nextcloud               Install Nextcloud container
  --smtp                    Install SMTP container
  --rvprx                   Install reverse proxy container
  --mariadb                 Install MariaDB container
  --collabora               Install Collabora container
  --fqdn DOMAIN             Set Nextcloud FQDN
  --collabora-fqdn DOMAIN   Set Collabora FQDN
  --smtp-fqdn DOMAIN        Set SMTP FQDN
  --http-port PORT          Set HTTP port
  --https-port PORT         Set HTTPS port
  --collabora-port PORT     Set Collabora port
  --skip-dns-check         Skip FQDN DNS validation
  --port-forward SPEC       Add extra port forward (HOST_PORT:CONTAINER[:CONTAINER_PORT])
  --use-lxd-proxy          Use LXD proxy devices instead of iptables
  -h, --help                Show this help
USAGE
}

components=()
port_forwards=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            components=(smtp rvprx mariadb cloud collabora)
            shift
            ;;
        --nextcloud)
            components+=(cloud)
            shift
            ;;
        --smtp)
            components+=(smtp)
            shift
            ;;
        --rvprx)
            components+=(rvprx)
            shift
            ;;
        --mariadb)
            components+=(mariadb)
            shift
            ;;
        --collabora)
            components+=(collabora)
            shift
            ;;
        --fqdn)
            FQDN_OVERRIDE="$2"
            shift 2
            ;;
        --collabora-fqdn)
            FQDN_COLLABORA_OVERRIDE="$2"
            shift 2
            ;;
        --smtp-fqdn)
            FQDN_SMTP_OVERRIDE="$2"
            shift 2
            ;;
        --http-port)
            HTTP_PORT_OVERRIDE="$2"
            shift 2
            ;;
        --https-port)
            HTTPS_PORT_OVERRIDE="$2"
            shift 2
            ;;
        --collabora-port)
            COLLABORA_PORT_OVERRIDE="$2"
            shift 2
            ;;
        --skip-dns-check)
            SKIP_DNS_CHECK=1
            shift
            ;;
        --port-forward)
            port_forwards+=("$2")
            shift 2
            ;;
        --use-lxd-proxy)
            USE_LXD_PROXY=1
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_help
            exit 1
            ;;
    esac
    # If --all specified, ignore other options
    if [[ ${components[0]} == "smtp" && ${#components[@]} -eq 5 ]]; then
        break
    fi
done

if [[ ${#components[@]} -eq 0 ]]; then
    show_help
    exit 1
fi

# Remove duplicates
mapfile -t components < <(printf '%s\n' "${components[@]}" | sort -u)

# Run base installation script once
export FQDN_OVERRIDE FQDN_COLLABORA_OVERRIDE FQDN_SMTP_OVERRIDE \
       HTTP_PORT_OVERRIDE HTTPS_PORT_OVERRIDE COLLABORA_PORT_OVERRIDE \
       SKIP_DNS_CHECK PORT_FORWARDS="${port_forwards[*]}" USE_LXD_PROXY

./10_install_start.sh

# Only continue if the first stage didn't request a logout (user already in lxd group)
if ! id -nG "$USER" | grep -qw lxd; then
    exit 0
fi

# Pass component list to next script
./11_install_next.sh "${components[@]}"
