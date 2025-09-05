#!/usr/bin/env bash
set -e

easyrsa_dir=/etc/easy-rsa
server_keys_dir=/etc/openvpn/server/keys


generate_client() {
  local name="$1"
  declare -n kwargs=$2
  local revoke="${kwargs[revoke]:-false}"

  if $revoke; then
    revoke_client "$name"
  fi

  echo "Generate certificate and key for client: $name"
  run_easyrsa build-client-full "$name" nopass
}


get_remote_ip() {
    local services=(2ip.ru icanhazip.com ifconfig.me api.ipify.org)

    for url in "${services[@]}"; do
      curl -sf -4 --connect-timeout 10 "$url" && break
    done
}


revoke_client() {
  local name="$1"

  echo "Revocation of a previously issued certificate for a client: $name"
  run_easyrsa revoke "$name"

  echo 'Generate OpenVPN Revocation Certificate'
  run_easyrsa gen-crl

  echo "Copying the CRL file to the OpenVPN server directory: $server_keys_dir"
  cp ./pki/crl.pem "$server_keys_dir"/

  echo 'Restarting OpenVPN server'
  systemctl restart openvpn-server@server
}


run_easyrsa() {
  EASYRSA_BATCH=1 ./easyrsa "$@" > /dev/null 2> >(sed -n '/^Easy-RSA error:/,//p' >&2)
}


show_config() {
  local name="$1"
  declare -n kwargs=$2

  if [[ ! -f "./pki/issued/${name}.crt" ]] || [[ ! -f "./pki/private/${name}.key" ]]
  then
    echo >&2 "Invalid argument value: client with '$name' not found."
    exit 1
  fi

  local CA_CERT CLIENT_CERT CLIENT_KEY
  CA_CERT="$(sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' ./pki/ca.crt)"
  CLIENT_CERT="$(sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' "./pki/issued/${name}.crt")"
  CLIENT_KEY="$(sed -n '/BEGIN PRIVATE KEY/,/END PRIVATE KEY/p' "./pki/private/${name}.key")"

  export PROTO="${kwargs[proto]:-udp}"
  export REMOTE="${kwargs[remote]:-$(get_remote_ip)}"
  export REMOTE_PORT="${kwargs[port]:-1194}"
  export CA_CERT
  export CLIENT_CERT
  export CLIENT_KEY

  envsubst < "/etc/openvpn/templates/client-${PROTO}.tmpl"
}


usage() {
	case "$1" in
		generate)
			cat 1>&2 <<-ENDOFUSAGE

			Adds a new OpenVPN client

			Usage: $(basename "$0") $1 NAME [OPTIONS]"

			Positional:
			  NAME STRING           CN (name) of the client

			Options:
			  -f --revoke BOOL      Recreate the client, overwriting the old private key and certificate

			ENDOFUSAGE
			;;
		revoke)
			cat 1>&2 <<-ENDOFUSAGE

			Revokes a previously issued certificate to a client

			Usage: $(basename "$0") $1 NAME [OPTIONS]"

			Positional:
			  NAME STRING           CN (name) of the client

			Options:
			  -n --name STRING      CN (name) of the client

			ENDOFUSAGE
			;;
		show)
			cat 1>&2 <<-ENDOFUSAGE

			Outputs to STDOUT the OVPN configuration file for the client with the given CN

			Usage: $(basename "$0") $1 NAME [OPTIONS]"

			Positional:
			  NAME STRING           CN (name) of the client

			Options:
			  -r --ip
			     --remote STRING    OpenVPN server host, default - external IP address
			  -p --port STRING      OpenVPN server port, default - 1194
			  --proto STRING        Server connection protocol (udp or tcp)

			ENDOFUSAGE
			;;
		*)
			cat 1>&2 <<-ENDOFUSAGE

			Utility for working with keys and certificates

			Usage: $(basename "$0") COMMAND NAME [OPTIONS]

			Commands:
			  generate  Create a new client
			  revoke    Revokes the client certificate
			  show      Show ovpn file for client

			ENDOFUSAGE
			;;
	esac
}


if [[ "$#" -lt 1 ]]; then
    usage
    exit 1
fi

cmd="$1"
shift

case "$cmd" in
  generate)
    declare -A optionsMap=()
    declare -A flagsMap=(
      [-f]="revoke"
      [--revoke]="revoke"
    )
    ;;
  revoke)
    declare -A optionsMap=()
    declare -A flagsMap=()
    ;;
  show)
    declare -A optionsMap=(
      [-r]="remote"
      [--ip]="remote"
      [--remote]="remote"
      [-p]="port"
      [--port]="port"
      [--proto]="proto"
    )
    declare -A flagsMap=()
    ;;
  *)
    echo >&2 "Unknown command: $cmd"
    usage
    exit 1
    ;;
esac

declare cli_positional=()
declare -A cli_options=()

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage "$cmd"
      exit 0
      ;;
    --*|-*)
      if [[ -v "optionsMap[$1]" ]]; then
        cli_options["${optionsMap[$1]}"]="$2"
        shift 2
      elif [[ -v "flagsMap[$1]" ]]; then
        cli_options["${flagsMap[$1]}"]=true
        shift 1
      else
        echo >&2 "Error: Unknown option $1"
        usage
        exit 1
      fi
      ;;
    *)
      cli_positional+=("$1")
      shift
      ;;
  esac
done

name="${cli_positional[0]}"

if [[ -z "$name" ]]; then
    echo >&2 "Required positional argument: name"
    usage "$cmd"
    exit 1
fi

cd "$easyrsa_dir" || exit 1

case "$cmd" in
  generate) generate_client "$name" cli_options ;;
  revoke) revoke_client "$name" cli_options ;;
  show) show_config "$name" cli_options ;;
esac
