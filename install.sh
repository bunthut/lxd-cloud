#!/bin/bash
set -e

show_help() {
    cat <<USAGE
Usage: $0 [OPTIONS]

Options:
  --all         Install all components
  --nextcloud   Install Nextcloud container
  --smtp        Install SMTP container
  --rvprx       Install reverse proxy container
  --mariadb     Install MariaDB container
  --collabora   Install Collabora container
  --fqdn DOMAIN             Set Nextcloud FQDN
  --collabora-fqdn DOMAIN   Set Collabora FQDN
  --smtp-fqdn DOMAIN        Set SMTP FQDN
  -h, --help    Show this help
USAGE
}

components=()

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
export FQDN_OVERRIDE FQDN_COLLABORA_OVERRIDE FQDN_SMTP_OVERRIDE
./10_install_start.sh

# Pass component list to next script
./11_install_next.sh "${components[@]}"
