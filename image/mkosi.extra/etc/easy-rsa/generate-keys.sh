#!/usr/bin/env bash


build_pki() {
    ./easyrsa init-pki
    EASYRSA_BATCH=1 EASYRSA_REQ_CN="P2P CA" ./easyrsa build-ca nopass
    EASYRSA_BATCH=1 ./easyrsa gen-dh
    EASYRSA_BATCH=1 ./easyrsa build-server-full server nopass nodatetime
    openvpn --genkey secret ./pki/ta.key
    EASYRSA_BATCH=1 ./easyrsa gen-crl
    EASYRSA_BATCH=1 ./easyrsa build-client-full "openvpn-client" nopass nodatetime
}


copy_server_keys() {
    local pki_dir="$1"
    local server_keys_dir="$2"
    local files=(ca.crt dh.pem ta.key crl.pem issued/server.crt private/server.key)
    local file

    for file in "${files[@]}"; do
        local dest
        dest="${server_keys_dir}/$(basename "$file")"

        if [[ ! -f "$dest" ]]; then
            cp "${pki_dir}/${file}" "$dest"
        fi
    done
}


main() {
    local easyrsa_dir="${1:-/etc/easy-rsa}"
    local server_keys_dir="${2:-/etc/openvpn/server/keys}"

    cd "$easyrsa_dir" || exit 1

    if [[ ! -f easyrsa ]]; then
        cp -r /usr/share/easy-rsa/* ./
        chmod 700 .
    fi

    if [[ ! -f ./pki/ca.crt ]]; then
        build_pki
    fi

    copy_server_keys ./pki "$server_keys_dir"
}


main "$1" "$2"
