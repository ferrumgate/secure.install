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
    . ./sh/docker.sh

    if [ "$INSTALL" = "docker" ]; then
        #prerequities
        #docker_install
        #docker_network_bridge_configure ferrum

        # prepare folder permission to only root
        chmod -R 600 $(pwd)
        DOCKER_FILE=ferrum.docker-compose.yaml
        cp $DOCKER_FILE compose.yaml
        DOCKER_FILE=compose.yaml

        if [ $ENV_FOR != "PROD" ]; then # for test use local private registry

            sed -i 's#??PRIVATE_REGISTRY/#registry.ferrumgate.local/#g' $DOCKER_FILE
        else
            sed -i 's#??PRIVATE_REGISTRY/##g' $DOCKER_FILE

        fi

        GATEWAY_ID=$(cat /dev/urandom | tr -dc '[:alnum:]' | fold -w 16 | head -n 1)
        REDIS_PASS=$(cat /dev/urandom | tr -dc '[:alnum:]' | fold -w 64 | head -n 1)
        ES_PASS=$(cat /dev/urandom | tr -dc '[:alnum:]' | fold -w 64 | head -n 1)
        ENCRYPT_KEY=$(cat /dev/urandom | tr -dc '[:alnum:]' | fold -w 32 | head -n 1)
        if [ $ENV_FOR != "PROD" ]; then
            GATEWAY_ID=4s6ro4xte8009p96
            REDIS_PASS=1dpkz8g8xg6e8tfz3tv1usddjhcu1m81pjcp2ai9je08zlop73t64eis6y0thxlv
            ES_PASS=ux4eyrkbr47z6sckyf9zmavvgzxgvrzebsh082dumfk59j3b5ti9fvy95s7sybmx
            ENCRYPT_KEY=6ydkxusirp6jy3ahttvd6m9v84axa0xt

        fi
        # set gateway id
        info "configuring gateway id"
        sed -i "s/??GATEWAY_ID/$GATEWAY_ID/g" $DOCKER_FILE

        # set redis password
        info "configuring redis password"
        sed -i "s/??REDIS_PASS/$REDIS_PASS/g" $DOCKER_FILE

        info "configuring enc key"
        sed -i "s/??ENCRYPT_KEY/$ENCRYPT_KEY/g" $DOCKER_FILE

        info "configuring es password"
        sed -i "s/??ES_PASS/$ES_PASS/g" $DOCKER_FILE

        docker compose -f $DOCKER_FILE down
        docker compose -f $DOCKER_FILE pull
        docker compose -f $DOCKER_FILE -p ferrumgate up -d --remove-orphans

    fi
}

main $*
