#!/usr/bin/env bash
set -e


build_pki() {
    echo 'Инициализация PKI'
    ./easyrsa init-pki

    echo 'Генерация сертификата и ключа центра сертификации (CA)'
    EASYRSA_BATCH=1 EASYRSA_REQ_CN="OpenVPN CA" ./easyrsa build-ca nopass

    echo 'Генерация ключей Диффи-Хеллмана'
    EASYRSA_BATCH=1 ./easyrsa gen-dh

    echo 'Генерация сертификата и закрытого ключа для сервера OpenVPN'
    EASYRSA_BATCH=1 ./easyrsa build-server-full server nopass nodatetime

    echo 'Генерация ключа кода аутентификации сообщений на основе хэша (HMAC)'
    # для предотвращения DoS-атак и переполнения портов UDP
    openvpn --genkey secret ./pki/ta.key

    echo 'Генерация сертификата отзыва'
    EASYRSA_BATCH=1 ./easyrsa gen-crl
}


easyrsa_dir=/etc/easy-rsa
server_keys_dir=/etc/openvpn/server/keys

cd "$easyrsa_dir" || exit 1


if [[ ! -f ./pki/ca.crt ]]
then
    build_pki
fi


if [[ ! -d "$server_keys_dir" ]] || \
   [[ -z "$(find "$server_keys_dir" -mindepth 1 -print -quit)" ]]
then
    echo 'Копирование сертификатов и ключей в директорию сервера OpenVPN'
    mkdir -p "$server_keys_dir"
    cp -rp ./pki/{ca.crt,dh.pem,ta.key,crl.pem,issued/server.crt,private/server.key} \
           "$server_keys_dir"
fi


if [[ ! -f ./pki/issued/client.crt ]] && \
   [[ ! -f ./pki/private/client.key ]] && \
   [[ ! -f ./pki/reqs/client.req ]]
then
    echo 'Генерация клиентского сертификата и ключа по умолчанию'
    generate-client-key -n client > /root/client.ovpn
fi
