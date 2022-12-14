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
#### verify existence of network downloader executable
verify_command() {
    # Return failure if it doesn't exist or is no executable
    [ -x "$(command -v $1)" ] || return 1

    return 0
}

#### download from github url ---
download() {
    echo $*
    [ $# -eq 2 ] || fatal 'download needs exactly 2 arguments'

    case $DOWNLOADER in
    curl)
        curl -o $1 -sfL $2
        ;;
    wget)
        wget -qNO $1 $2
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
    verify_downloader curl || verify_downloader wget || fatal 'can not find curl or wget for downloading files'
    verify_command unzip || fatal "can not find unzip command"
    download install.zip https://github.com/ferrumgate/secure.install/archive/refs/heads/master.zip
    unzip install.zip
    mv secure.install-master secure.install
    cd secure.install
}

print_usage() {
    echo "usage"
    echo "  ./install.sh [ -h | --help ]          -> prints help"
    echo "  ./install.sh [ -d | --docker ]        -> install with docker"
    echo "  ./install.sh [ -s | --docker-swarm ]  -> install with docker-swarm"

}

install_services() {
    cat >/etc/systemd/system/ferrumgate.service <<EOF
[Unit]
Description=%i service with docker compose
PartOf=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=/etc/ferrumgate
ExecStart=docker compose -f ferrumgate.docker.yaml up -d --remove-orphans
ExecStop=docker compose -f ferrumgate.docker.yaml down

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable ferrumgate

}
ensure_root() {
    WUSER=$(id -u)
    if [ ! "$WUSER" -eq 0 ]; then
        echo "root privilges need"
        exit 1
    fi

}
create_certificates() {
    domain=secure.ferrumgate.local
    tmpFolder=/tmp
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout ${tmpFolder}/${domain}.key -out ${tmpFolder}/${domain}.crt -subj "/CN=${domain}/O=${domain}" 2>/dev/null
    echo ${tmpFolder}/${domain}
}

main() {
    ensure_root
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
        prerequities
        docker_install
        docker_network_bridge_configure ferrum

        # prepare folder permission to only root
        chmod -R 600 $(pwd)
        DOCKER_FILE=docker.yaml
        cp $DOCKER_FILE compose.yaml
        DOCKER_FILE=compose.yaml

        if [ $ENV_FOR != "PROD" ]; then # for test use local private registry

            sed -i 's#??PRIVATE_REGISTRY/#registry.ferrumgate.local/#g' $DOCKER_FILE
        else
            sed -i 's#??PRIVATE_REGISTRY/##g' $DOCKER_FILE

        fi
        LOG_LEVEL=info
        GATEWAY_ID=$(cat /dev/urandom | tr -dc '[:alnum:]' | fold -w 16 | head -n 1)
        REDIS_PASS=$(cat /dev/urandom | tr -dc '[:alnum:]' | fold -w 64 | head -n 1)
        ES_PASS=$(cat /dev/urandom | tr -dc '[:alnum:]' | fold -w 64 | head -n 1)
        ENCRYPT_KEY=$(cat /dev/urandom | tr -dc '[:alnum:]' | fold -w 32 | head -n 1)
        SSL_FILE=$(create_certificates)

        SSL_PUB=$(cat ${SSL_FILE}.crt | base64 -w 0)
        SSL_KEY=$(cat ${SSL_FILE}.key | base64 -w 0)

        if [ $ENV_FOR != "PROD" ]; then
            GATEWAY_ID=4s6ro4xte8009p96
            REDIS_PASS=1dpkz8g8xg6e8tfz3tv1usddjhcu1m81pjcp2ai9je08zlop73t64eis6y0thxlv
            ES_PASS=ux4eyrkbr47z6sckyf9zmavvgzxgvrzebsh082dumfk59j3b5ti9fvy95s7sybmx
            ENCRYPT_KEY=6ydkxusirp6jy3ahttvd6m9v84axa0xt
            LOG_LEVEL=debug

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

        info "configuring log level"
        sed -i "s/??LOG_LEVEL/$LOG_LEVEL/g" $DOCKER_FILE

        info "configuring ssl certificates"
        sed -i "s/??SSL_PUB/$SSL_PUB/g" $DOCKER_FILE
        sed -i "s/??SSL_KEY/$SSL_KEY/g" $DOCKER_FILE

        mkdir -p /etc/ferrumgate
        cp -f $DOCKER_FILE /etc/ferrumgate/ferrumgate.docker.yaml
        chmod 600 /etc/ferrumgate/ferrumgate.docker.yaml

        info "installing services"
        install_services

        info "copy script files"
        cp sh/run/ferrumgate.sh /usr/local/bin/ferrumgate
        chmod +x /usr/local/bin/ferrumgate

        #docker compose -f $DOCKER_FILE down
        #docker compose -f $DOCKER_FILE pull
        #docker compose -f $DOCKER_FILE -p ferrumgate up -d --remove-orphans
        info "system is ready"

    fi
}

main $*
