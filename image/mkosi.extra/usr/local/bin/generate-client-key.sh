#!/usr/bin/env bash
set -e


generate_client() {
  declare -n kwargs=$1
  local name="${kwargs[name]}"
  local rewrite="${kwargs[rewrite]:-false}"

  if $rewrite
  then
    rm -f ./pki/reqs/client.req ./pki/issued/client.crt ./pki/private/client.key
  fi

  if ! EASYRSA_BATCH=1 ./easyrsa build-client-full "$name" nopass >/dev/null 2> >(sed -n '/^Easy-RSA error:/,//p' >&2)
  then
    exit 1
  fi
}


get_remote_ip() {
    local services=(2ip.ru icanhazip.com ifconfig.me api.ipify.org)

    for url in "${services[@]}"; do
        curl -sf -4 --connect-timeout 10 "$url" && break
    done
}


show_config() {
  declare -n kwargs=$1
  local name="${kwargs[name]}"

  if [[ ! -f "./pki/issued/${name}.crt" ]] || [[ ! -f "./pki/private/${name}.key" ]]
  then
    echo >&2 "Invalid argument value: -n or --name - client not found."
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

			Usage: $(basename "$0") $1 --name NAME [OPTIONS]"

			Options:
			  -n --name STRING      CN (name) of the client
			  -f --rewrite BOOL     Recreate the client, overwriting the old private key and certificate

			ENDOFUSAGE
			;;
		show)
		  cat 1>&2 <<-ENDOFUSAGE

			Outputs to STDOUT the OVPN configuration file for the client with the given CN

			Usage: $(basename "$0") $1 --name NAME [OPTIONS]"

			Options:
			  -n --name STRING      CN (name) of the client
			  -r --ip
			     --remote STRING    OpenVPN server host, default - external IP address
			  -p --port STRING      OpenVPN server port, default - 1194
			  --proto STRING        Server connection protocol (udp or tcp)

			ENDOFUSAGE
			;;
		*)
			cat 1>&2 <<-ENDOFUSAGE

			Utility for working with keys and certificates

			Usage: $(basename "$0") COMMAND [OPTIONS]

			Commands:
			  generate  Create a new client
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
    declare -A optionsMap=(
      [-n]="name"
      [--name]="name"
    )
    declare -A flagsMap=(
      [-f]="rewrite"
      [--rewrite]="rewrite"
    )
    ;;
  show)
    declare -A optionsMap=(
      [-n]="name"
      [--name]="name"
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

declare -A arguments=()

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage "$cmd"
      exit 0
      ;;
    *)
      if [[ -v "optionsMap[$1]" ]]; then
        arguments["${optionsMap[$1]}"]="$2"
        shift 2
      elif [[ -v "flagsMap[$1]" ]]; then
        arguments["${flagsMap[$1]}"]=true
        shift 1
      else
        echo >&2 "Error: Unknown option $1"
        usage
        exit 1
      fi
      ;;
  esac
done

if [[ -z "${arguments[name]}" ]]; then
    echo >&2 "Required argument: -n or --name"
    usage "$cmd"
    exit 1
fi

cd /etc/easy-rsa || exit 1

case "$cmd" in
  generate) generate_client arguments ;;
  show) show_config arguments ;;
esac
