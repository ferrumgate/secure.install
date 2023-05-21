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
#URL="https://raw.githubusercontent.com/ferrumgate/secure.install/master"

#### ensures $URL is empty or begins with https://, exiting fatally otherwise
#verify_install_url() {
#    URL=$0
#    case "${URL}" in
#    "") ;;
#
#    https://*) ;;
#
#    *)
#        fatal "Only https:// URLs are supported "
#        ;;
#    esac
#}

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
VERSION=1.9.0
download_and_verify() {
    info "installing version $VERSION"
    [ "$ENV_FOR" != "PROD" ] && return 0
    verify_downloader curl || verify_downloader wget || fatal 'can not find curl or wget for downloading files'
    verify_command unzip || fatal "can not find unzip command"
    ## download version
    download install.zip https://github.com/ferrumgate/secure.install/archive/refs/tags/v$VERSION.zip
    unzip install.zip
    mv secure.install-$VERSION secure.install
    cd secure.install
}

print_usage() {
    echo "usage"
    echo "  ./install.sh [ -h | --help ]          -> prints help"
    echo "  ./install.sh [ -d | --docker ]        -> install with docker"
    echo "  ./install.sh [ -b | --bridge-network 10.9.0.0/24 ] -> docker bridge network"
    echo "  ./install.sh [ -v | --version 1.6.0 ]  -> install custom version"

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
ExecStart=ferrumgate --start-gateways
ExecStop=ferrumgate --stop-gateways

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
    domain=secure.ferrumgate.zero
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout ${domain}.key -out ${domain}.crt -subj "/CN=${domain}/O=${domain}" 2>/dev/null
    echo ${domain}
}

main() {
    ensure_root
    # install type
    local INSTALL="docker"
    local BRIDGE_NETWORK="10.9.0.0/24"
    ARGS=$(getopt -o 'hdv:b:' --long 'help,docker,version:,bridge-network:' -- "$@") || exit
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
        -v | --version)
            VERSION="$2"
            shift 2
            ;;
        -b | --bridge-network)
            BRIDGE_NETWORK="$2"
            shift 2
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

        if [ $ENV_FOR = "PROD" ]; then
            prerequities
            docker_install
            #docker_network_bridge_configure ferrum $BRIDGE_NETWORK
        fi

        # prepare folder permission to only root
        chmod -R 600 $(pwd)
        DOCKER_FILE=docker.yaml
        cp $DOCKER_FILE compose.yaml
        DOCKER_FILE=compose.yaml

        if [ $ENV_FOR != "PROD" ]; then # for test use local private registry

            sed -i 's#??PRIVATE_REGISTRY/#registry.ferrumgate.zero/#g' $DOCKER_FILE
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
        rm ${SSL_FILE}.crt && rm ${SSL_FILE}.key

        if [ $ENV_FOR != "PROD" ]; then
            GATEWAY_ID=4s6ro4xte8009p96
            REDIS_PASS=1dpkz8g8xg6e8tfz3tv1usddjhcu1m81pjcp2ai9je08zlop73t64eis6y0thxlv
            ES_PASS=ux4eyrkbr47z6sckyf9zmavvgzxgvrzebsh082dumfk59j3b5ti9fvy95s7sybmx
            ENCRYPT_KEY=6ydkxusirp6jy3ahttvd6m9v84axa0xt
            LOG_LEVEL=debug

        fi
        # set gateway id
        info "configuring gateway id"
        #sed -i "s/??GATEWAY_ID/$GATEWAY_ID/g" $DOCKER_FILE

        # set redis password
        info "configuring redis password"
        #sed -i "s/??REDIS_PASS/$REDIS_PASS/g" $DOCKER_FILE
        #sed -i "s/??REDIS_LOCAL_PASS/$REDIS_PASS/g" $DOCKER_FILE

        info "configuring enc key"
        #sed -i "s/??ENCRYPT_KEY/$ENCRYPT_KEY/g" $DOCKER_FILE

        info "configuring es password"
        #sed -i "s/??ES_PASS/$ES_PASS/g" $DOCKER_FILE

        info "configuring log level"
        #sed -i "s/??LOG_LEVEL/$LOG_LEVEL/g" $DOCKER_FILE

        info "configuring ssl certificates"
        #sed -i "s/??SSL_PUB/$SSL_PUB/g" $DOCKER_FILE
        #sed -i "s/??SSL_KEY/$SSL_KEY/g" $DOCKER_FILE

        mkdir -p /etc/ferrumgate
        ENV_FILE_ETC=/etc/ferrumgate/ferrumgate.$GATEWAY_ID.env
        cat >$ENV_FILE_ETC <<EOF
MODE=single
GATEWAY_ID=$GATEWAY_ID
REDIS_HOST=redis:6379
REDIS_HOST_SSH=redis#6379
REDIS_PASS=$REDIS_PASS
REDIS_LOCAL_HOST=redis-local:6379
REDIS_LOCAL_PASS=$REDIS_PASS
ENCRYPT_KEY=$ENCRYPT_KEY
ES_HOST=http://es:9200
ES_USER=elastic
ES_PASS=$ES_PASS
LOG_LEVEL=$LOG_LEVEL
REST_HTTP_PORT=80
REST_HTTPS_PORT=443
SSH_PORT=9999
EOF

        DOCKER_FILE_ETC=/etc/ferrumgate/ferrumgate.$GATEWAY_ID.yaml
        cp -f $DOCKER_FILE $DOCKER_FILE_ETC

        chmod 600 $DOCKER_FILE_ETC
        chmod 600 $ENV_FILE_ETC

        info "installing services"
        install_services

        info "copy script files"
        sed -i "s/??VERSION/$VERSION/g" sh/run/ferrumgate.sh
        cp sh/run/ferrumgate.sh /usr/local/bin/ferrumgate
        chmod +x /usr/local/bin/ferrumgate

        if [ $ENV_FOR != "PROD" ]; then
            docker compose -f $DOCKER_FILE_ETC --env-file $ENV_FILE_ETC down
            docker compose -f $DOCKER_FILE_ETC --env-file $ENV_FILE_ETC pull
            docker compose -f $DOCKER_FILE_ETC --env-file $ENV_FILE_ETC --profile single -p ferrumgate-${GATEWAY_ID} up -d --remove-orphans
        fi
        info "system is ready"

    fi
}

main $*
