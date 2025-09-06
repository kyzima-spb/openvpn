#!/usr/bin/env bash
set -e


get_free_port() {
  perl -MIO::Socket::INET -e '
    $s = IO::Socket::INET->new(Listen=>1, LocalAddr=>"127.0.0.1", LocalPort=>0);
    print $s->sockport;
  '
}


run_command_in_container() {
  local name="$1"
  shift

  if systemctl -q is-active "systemd-nspawn@${name}.service"
  then
    systemd-run -q --wait --pipe -M "$name" "$@"
  elif [ -d "/var/lib/machines/$name" ] || [ -f "/var/lib/machines/${name}.raw" ]
  then
    systemd-nspawn -q --pipe -U -M "$name" "$@"
  else
    echo >&2 "Could not get path to machine: No machine '$name' known"
    exit 1
  fi
}


backup() {
	local name="$1"
	echo >&2 "Files from machine '$name' will be backup to STDOUT"
	run_command_in_container "$name" tar -cPJO \
	  /etc/easy-rsa/pki \
	  /etc/openvpn/server/keys \
	  /etc/openvpn/server/server.conf
}


restore() {
  local name="$1"
  echo >&2 "Files for machine '$name' will be restored from STDIN"
  run_command_in_container "$name" tar -C / -xPJf -
}


install_requirements() {
  local public_key="$1"

	apt-get update -qq

	if ! command -v machinectl > /dev/null
	then
		DEBIAN_FRONTEND=noninteractive apt-get install -qq -y systemd-container
	fi

	if ! command -v gpg > /dev/null
	then
		DEBIAN_FRONTEND=noninteractive apt-get install -qq -y gnupg
	fi

	gpg -k > /dev/null
  gpg \
    --no-default-keyring \
    --keyring /etc/systemd/import-pubring.gpg \
    --keyserver hkps://keyserver.ubuntu.com \
    --receive-keys "$public_key"

	systemctl enable --now systemd-networkd.service
}


install() {
  declare -n kwargs=$1
	local name="${kwargs[name]}"
	local image="${kwargs[image]:-https://kyzima-spb.github.io/openvpn/rootfs.tar.xz}"
	local port="${kwargs[port]:-$(get_free_port)}"
	local public_key="${kwargs[public_key]:-0xA2AFF7EB363E6C8DD27655AD62CD962F89DDC0CD}"

	install_requirements "$public_key"

	if [[ -f "$image" ]]
	then
		machinectl import-tar "$image" "$name"
	else
		machinectl pull-tar "$image" "$name"
	fi

	local nspawn_dir="/etc/systemd/nspawn"
	local nspawn_file="${nspawn_dir}/${name}.nspawn"

	mkdir -p "$nspawn_dir"
	
	if [[ ! -f "$nspawn_file" ]]
	then
		cat > "$nspawn_file" <<- EOF
			[Exec]
			NotifyReady=yes
			PrivateUsers=yes

			[Network]
			VirtualEthernet=yes
			Port=tcp:${port}:1194
			Port=udp:${port}:1194
		EOF
	fi

	machinectl enable "$name"
	machinectl start "$name"
	
	echo -n >&2 "Wait creation OVPN config file."

	while ! systemd-run -q -M "$name" --wait --pipe /usr/bin/journalctl -u openvpn-generate-keys | \
	        grep 'Deactivated successfully.' > /dev/null
	do
		echo >&2 -n '.'
		sleep 2
	done

	echo >&2 "[OK]"

	machinectl shell -q "$name" /usr/local/bin/generate-client-key show client \
	                            --remote "${kwargs[remote]}" \
	                            --port "$port" \
	                            --proto "${kwargs[proto]}"
}


uninstall() {
	local name="$1"

	if machinectl show "$name" > /dev/null
	then
		machinectl poweroff "$name"
	fi

	if machinectl show-image "$name" > /dev/null
	then
		machinectl disable "$name"

		while ! machinectl remove "$name" 2>/dev/null
		do
			sleep 1
		done
	fi

	rm -f "/etc/systemd/nspawn/${name}.nspawn"
}


usage() {
	case "$1" in
		backup)
			cat 1>&2 <<-ENDOFUSAGE

			Creates a tar.xz archive to STDOUT with a copy of all files that cannot be restored when creating a new container.

			Usage: $(basename "$0") $1 [OPTIONS]"

			Options:
			  -n --name STRING      Container name (used by machinectl and .nspawn config file)

			ENDOFUSAGE
			;;
		restore)
			cat 1>&2 <<-ENDOFUSAGE

			Restores container files from the archive in STDIN that was previously created by the backup command.

			Usage: $(basename "$0") $1 [OPTIONS]"

			Options:
			  -n --name STRING      Container name (used by machinectl and .nspawn config file)

			ENDOFUSAGE
			;;
		install)
			cat 1>&2 <<-ENDOFUSAGE

			Install and start a systemd-nspawn container with given image

			Usage: $(basename "$0") $1 [OPTIONS]"

			Options:
			  -n --name STRING      Container name (used by machinectl and .nspawn config file)
			  --url --image STRING  Path to a rootfs tarball or URL supported by machinectl pull-tar
			  --ip --remote STRING  Server host, default - external IP address
			  -p --port STRING      Server port, default - random free
			  --proto STRING        Server connection protocol
			  --public-key STRING   The public GPG that the image is signed with

			ENDOFUSAGE
			;;
		uninstall)
			cat 1>&2 <<-ENDOFUSAGE

			Stops and uninstall a systemd-nspawn container with given name

			Usage: $(basename "$0") $1 [OPTIONS]"

			Options:
			  -n --name STRING      Container name (used by machinectl and .nspawn config file)

			ENDOFUSAGE
			;;
		*)
			cat 1>&2 <<-ENDOFUSAGE

			Utility for working with systemd-nspawn container

			Usage: $(basename "$0") COMMAND [OPTIONS]

			Commands:
			  backup        Backup of non-recoverable container files
			  install       Installing a container on the current host
			  restore       Recovering container files from backup
			  uninstall     Remove container from current host

			Options:
			  -h --help     Show general help
			  -v --version  Show script version

			ENDOFUSAGE
			;;
	esac
}


main() {
	if [[ "$(whoami)" != 'root' ]]
	then
		echo >&2 "You have no permission to run $0 as non-root user. Use sudo"
		exit 1
	fi

	local cmd='install'

	case "$1" in
	  -h|--help)
	    usage
	    exit
	    ;;
	  -v|--version)
	    echo 'Not implemented :)'
	    exit
	    ;;
	  backup|restore|install|uninstall)
      cmd="$1"
	    shift
	    ;;
	  [!-]*)
	    echo >&2 "Unknown command: $1"
      usage
      exit 1
	    ;;
	esac

  declare -A options_map=(
    [-n]="name"
    [--name]="name"
  )
  declare -A flags_map=()

  case "$cmd" in
    install)
      options_map+=(
        [--url]="image"
        [--image]="image"
        [--ip]="remote"
        [--remote]="remote"
        [-p]="port"
        [--port]="port"
        [--proto]="proto"
        [--public-key]="public_key"
      )
      ;;
  esac

  declare -A cli_options=(
    [name]="p2p"
  )

  while [[ "$#" -gt 0 ]]
  do
    case "$1" in
      -h|--help)
        usage "$cmd"
        exit 0
        ;;
      *)
        if [[ -v "options_map[$1]" ]]; then
          cli_options["${options_map[$1]}"]="$2"
          shift 2
        elif [[ -v "flags_map[$1]" ]]; then
          cli_options["${flags_map[$1]}"]=true
          shift 1
        else
          echo >&2 "Error: Unknown option $1"
          usage "$cmd"
          exit 1
        fi
        ;;
    esac
  done

  case "$cmd" in
    backup) backup "${cli_options[name]}" ;;
    restore) restore "${cli_options[name]}" ;;
    install) install cli_options ;;
    uninstall) uninstall "${cli_options[name]}" ;;
  esac
}


main "$@"
