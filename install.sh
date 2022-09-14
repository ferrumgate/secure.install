#!/bin/sh
set -e
set -o noglob

#usage
# ENV_FOR=TEST ./install.sh

#### log functions
info() {
    echo '[INFO] ' "$@"
}
warn() {
    echo '[WARN] ' "$@" >&2
}
error() {
    echo '[ERROR] ' "$@" >&2
}
fatal() {
    echo '[FATAL] ' "$@" >&2
    exit 1
}

ENV_FOR=${ENV_FOR:="PROD"}
URL="https://raw.githubusercontent.com/ferrumgate/secure.install/master"

#### ensures $URL is empty or begins with https://, exiting fatally otherwise
verify_install_url() {
    URL=$0
    case "${URL}" in
    "") ;;

    https://*) ;;

    *)
        fatal "Only https:// URLs are supported "
        ;;
    esac
}

#### set arch and suffix, fatal if architecture not supported
setup_verify_arch() {
    if [ -z "$ARCH" ]; then
        ARCH=$(uname -m)
    fi
    case $ARCH in
    amd64)
        ARCH=amd64
        SUFFIX=
        ;;
    x86_64)
        ARCH=amd64
        SUFFIX=
        ;;
    *)
        fatal "unsupported architecture $ARCH"
        ;;
    esac
}

#### verify existence of network downloader executable
verify_downloader() {
    # Return failure if it doesn't exist or is no executable
    [ -x "$(command -v $1)" ] || return 1

    # Set verified executable as our downloader program and return success
    DOWNLOADER=$1
    return 0
}

#### download from github url ---
download() {
    [ $# -eq 2 ] || fatal 'download needs exactly 2 arguments'

    case $DOWNLOADER in
    curl)
        curl -o $1 -sfL $2
        ;;
    wget)
        wget -qO $1 $2
        ;;
    *)
        fatal "Incorrect executable '$DOWNLOADER'"
        ;;
    esac

    # Abort if download command failed
    [ $? -eq 0 ] || fatal 'Download failed'
}

download_and_verify() {
    [ "$ENV_FOR" != "PROD" ] && return 0
    mkdir -p ./sh
    verify_downloader curl || verify_downloader wget || fatal 'can not find curl or wget for downloading files'
    download "$*"
}

print_usage() {
    echo "usage"
    echo "  ./install.sh -h (--help)        -> prints help"
    echo "  ./install.sh -d (--docker)      -> install with docker"
    echo "  ./install.sh -s (--docker-swarm)-> install with docker-swarm"

}

main() {
    # install type
    local INSTALL="docker"

    ARGS=$(getopt -o 'hds' --long 'help,docker,docker-swarm' -- "$@") || exit
    eval "set -- $ARGS"
    local HELP=1
    while true; do
        case $1 in
        -h | --help)
            HELP=0
            shift
            break
            ;;
        -d | --docker)
            INSTALL="docker"
            shift
            break
            ;;
        -s | --docker-swarm)
            INSTALL="docker-swarm"
            shift
            break
            ;;
        --)
            shift
            break
            ;;
        *)
            print_usage
            exit 1
            ;; # error
        esac
    done

    [ $HELP -eq 0 ] && print_usage && exit 0
    info "check architecture"

    setup_verify_arch

    info "download install scripts from github"
    download_and_verify

    # after download add other scripts
    . ./sh/common.sh
    . ./sh/util.sh
    . ./sh/prerequities.sh
    . ./sh/microk8s.sh
    . ./sh/docker.sh
    . ./sh/docker.swarm.sh

    #prerequities
    #microk8s_install
    #microk8s_check_isworking
    #microk8s_enable_modules
    #microk8s_enable_ipvs || is_ipvs_changed=$?
    #debug "is_ipvs_changed:$is_ipvs_changed"
    #microk8s_prepare_networks || is_network_changed=$?

    #if [ is_ipvs_changed ] || [is_network_changed]; then
    #    info "restarting microk8s"
    #    microk8s_restart
    #fi
    if [ "$INSTALL" = "docker" ]; then
        #prerequities
        #docker_install
        #docker_network_bridge_configure ferrum
        enc_key=$(cat /dev/urandom | tr -dc '[:alnum:]' | fold -w ${1:-32} | head -n 1)
        if [ $ENV_FOR != "PROD" ]; then # for test use local private registry
            sed -i 's#_PRIVATE_REGISTRY/#registry.ferrumgate.local/#g' ferrum.docker.yaml
        fi

        docker compose -f ferrum.docker.yaml stop
        docker compose -f ferrum.docker.yaml pull
        docker compose -f ferrum.docker.yaml -p ferrumgate up -d

    fi
}

main $*
