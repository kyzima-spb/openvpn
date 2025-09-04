#!/usr/bin/env bash
set -e


get_remote_ip() {
    local services=(2ip.ru icanhazip.com ifconfig.me api.ipify.org)

    for url in "${services[@]}"; do
        curl -sf -4 --connect-timeout 10 "$url" && break
    done
}


name=''
rewrite=false

while getopts "n:f" o; do
  case "${o}" in
    n) name="${OPTARG}" ;;
    f) rewrite=true ;;
    *) usage ;;
  esac
done


if [[ -z "$name" ]]; then
    echo >&2 "Usage: $0 -n CLIENT_NAME"
    exit 1
fi

cd /etc/easy-rsa || exit 1

if $rewrite; then
    rm -f ./pki/reqs/client.req ./pki/issued/client.crt ./pki/private/client.key
fi

EASYRSA_BATCH=1 ./easyrsa build-client-full "$name" nopass

PROTO='udp'
REMOTE="$(get_remote_ip)"
CA_CERT="$(sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' ./pki/ca.crt)"
CLIENT_CERT="$(sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' "./pki/issued/${name}.crt")"
CLIENT_KEY="$(sed -n '/BEGIN PRIVATE KEY/,/END PRIVATE KEY/p' "./pki/private/${name}.key")"

export PROTO
export REMOTE
export CA_CERT
export CLIENT_CERT
export CLIENT_KEY

envsubst < "/etc/openvpn/templates/client-${PROTO}.tmpl"
