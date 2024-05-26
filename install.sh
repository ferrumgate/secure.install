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
    [ -x $(command -v "$1") ] || return 1

    # Set verified executable as our downloader program and return success
    DOWNLOADER=$1
    return 0
}
#### verify existence of network downloader executable
verify_command() {
    # Return failure if it doesn't exist or is no executable
    [ -x $(command -v "$1") ] || return 1

    return 0
}

#### download from github url ---
download() {
    echo "$*"
    [ $# -eq 2 ] || fatal 'download needs exactly 2 arguments'

    case $DOWNLOADER in
    curl)
        curl -o "$1" -sfL "$2"
        ;;
    wget)
        wget -qNO "$1" "$2"
        ;;
    *)
        fatal "Incorrect executable '$DOWNLOADER'"
        ;;
    esac

    # Abort if download command failed
    [ $? -eq 0 ] || fatal 'Download failed'
}
VERSION=2.0.0
download_and_verify() {
    if [ -d "./secure.install" ]; then
        rm -rf secure.install
    fi
    if [ -f "install.zip" ]; then
        rm -rf install.zip
    fi
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
ExecStart=ferrumgate --start-base-and-gateways
ExecStop=ferrumgate --stop-base-and-gateways

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
ETC_DIR=/etc/ferrumgate
SHARE_DIR=/usr/local/share/ferrumgate
get_config() {
    if [ $# -lt 1 ]; then
        error "no arguments supplied"
        exit 1
    fi
    local key="$1"

    file="$ETC_DIR/env"
    if [ ! -f $file ]; then
        echo ""
        return
    fi
    value=$(cat "$file" | grep "$key=" | cut -d"=" -f2-)
    echo "$value"
}

is_gateway_yaml() {
    result=$(echo "$1" | grep -E "gateway\.\w+\.yaml" || true)
    echo "$result"
}

create_cluster_ip() {
    local random=$(shuf -i 20-254 -n1)
    echo "169.254.254.$random"
}

create_cluster_private_key() {
    wg genkey | base64 -d | xxd -p -c 256
}
create_cluster_public_key() {
    echo "$1" | xxd -r -p | base64 | wg pubkey | base64 -d | xxd -p -c 256
}

main() {
    ensure_root

    # install type
    local INSTALL="docker"
    #local BRIDGE_NETWORK="10.9.0.0/24"
    ARGS=$(getopt -o 'hdv:b:' --long 'help,docker,version:' -- "$@") || exit
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

    mkdir -p $ETC_DIR
    mkdir -p $SHARE_DIR
    if [ "$INSTALL" = "docker" ]; then

        if [ $ENV_FOR = "PROD" ]; then
            prerequities
            docker_install
            #docker_network_bridge_configure ferrum $BRIDGE_NETWORK
        fi

        # prepare folder permission to only root
        chmod -R 600 $(pwd)

        LOG_LEVEL=$(get_config LOG_LEVEL)
        if [ -z "$LOG_LEVEL" ]; then
            LOG_LEVEL=info
        fi

        ROLES=$(get_config ROLES)
        if [ -z "$ROLES" ]; then
            ROLES="master:worker"
        fi

        DEPLOY_ID=$(get_config DEPLOY_ID)
        if [ -z "$DEPLOY_ID" ]; then
            ## this must be lowercase , we are using with docker compose -p
            DEPLOY_ID=$(cat /dev/urandom | tr -dc '[:alnum:]' | fold -w 16 | head -n 1 | tr '[:upper:]' '[:lower:]')
        fi

        NODE_ID=$(get_config NODE_ID)
        if [ -z "$NODE_ID" ]; then
            ## this must be lowercase , we are using with docker compose -p
            NODE_ID=$(cat /dev/urandom | tr -dc '[:alnum:]' | fold -w 16 | head -n 1 | tr '[:upper:]' '[:lower:]')
        fi

        GATEWAY_ID=$(get_config GATEWAY_ID)
        if [ -z "$GATEWAY_ID" ]; then
            ## this must be lowercase , we are using with docker compose -p
            GATEWAY_ID=$(cat /dev/urandom | tr -dc '[:alnum:]' | fold -w 16 | head -n 1 | tr '[:upper:]' '[:lower:]')
        fi

        REDIS_HOST=$(get_config REDIS_HOST)
        if [ -z "$REDIS_HOST" ]; then
            REDIS_HOST="redis:6379"
        fi

        REDIS_HA_HOST=$(get_config REDIS_HA_HOST)
        if [ -z "$REDIS_HA_HOST" ]; then
            REDIS_HA_HOST="redis-ha:7379"
        fi

        REDIS_HOST_SSH=$(echo $REDIS_HOST | sed 's/:/#/g')

        REDIS_PASS=$(get_config REDIS_PASS)
        if [ -z "$REDIS_PASS" ]; then
            REDIS_PASS=$(cat /dev/urandom | tr -dc '[:alnum:]' | fold -w 64 | head -n 1)
        fi

        REDIS_LOCAL_HOST=$(get_config REDIS_LOCAL_HOST)
        if [ -z "$REDIS_LOCAL_HOST" ]; then
            REDIS_LOCAL_HOST=redis-local:6381
        fi

        REDIS_LOCAL_PASS=$(get_config REDIS_LOCAL_PASS)
        if [ -z "$REDIS_LOCAL_PASS" ]; then
            REDIS_LOCAL_PASS=$REDIS_PASS
        fi

        REDIS_INTEL_HOST=$(get_config REDIS_INTEL_HOST)
        if [ -z "$REDIS_INTEL_HOST" ]; then
            REDIS_INTEL_HOST=redis-intel:6380
        fi

        REDIS_INTEL_HA_HOST=$(get_config REDIS_INTEL_HA_HOST)
        if [ -z "$REDIS_INTEL_HA_HOST" ]; then
            REDIS_INTEL_HA_HOST="redis-intel-ha:7380"
        fi

        REDIS_INTEL_PASS=$(get_config REDIS_INTEL_PASS)
        if [ -z "$REDIS_INTEL_PASS" ]; then
            REDIS_INTEL_PASS=$REDIS_PASS
        fi

        ES_HOST=$(get_config ES_HOST)
        if [ -z "$ES_HOST" ]; then
            ES_HOST=http://es:9200
        fi

        ES_HA_HOST=$(get_config ES_HA_HOST)
        if [ -z "$ES_HA_HOST" ]; then
            ES_HA_HOST="http://es-ha:10200"
        fi

        ES_USER=$(get_config ES_USER)
        if [ -z "$ES_USER" ]; then
            ES_USER=elastic
        fi

        ES_PASS=$(get_config ES_PASS)
        if [ -z "$ES_PASS" ]; then
            ES_PASS=$(cat /dev/urandom | tr -dc '[:alnum:]' | fold -w 64 | head -n 1)
        fi

        ES_INTEL_HOST=$(get_config ES_INTEL_HOST)
        if [ -z "$ES_INTEL_HOST" ]; then
            ES_INTEL_HOST=http://es:9200
        fi

        ES_INTEL_USER=$(get_config ES_INTEL_USER)
        if [ -z "$ES_INTEL_USER" ]; then
            ES_INTEL_USER=elastic
        fi

        ES_INTEL_PASS=$(get_config ES_INTEL_PASS)
        if [ -z "$ES_INTEL_PASS" ]; then
            ES_INTEL_PASS=$ES_PASS
        fi

        ENCRYPT_KEY=$(get_config ENCRYPT_KEY)

        if [ -z "$ENCRYPT_KEY" ]; then
            ENCRYPT_KEY=$(cat /dev/urandom | tr -dc '[:alnum:]' | fold -w 32 | head -n 1)
        fi

        MODE=$(get_config MODE)
        if [ -z "$MODE" ]; then
            MODE=single
        fi

        REST_HTTP_PORT=$(get_config REST_HTTP_PORT)
        if [ -z "$REST_HTTP_PORT" ]; then
            REST_HTTP_PORT=80
        fi

        REST_HTTPS_PORT=$(get_config REST_HTTPS_PORT)
        if [ -z "$REST_HTTPS_PORT" ]; then
            REST_HTTPS_PORT=443
        fi

        LOG_REPLICAS=$(get_config LOG_REPLICAS)
        if [ -z "$LOG_REPLICAS" ]; then
            LOG_REPLICAS=1
        fi

        LOG_PARSER_REPLICAS=$(get_config LOG_PARSER_REPLICAS)
        if [ -z "$LOG_PARSER_REPLICAS" ]; then
            LOG_PARSER_REPLICAS=1
        fi

        CLUSTER_NODE_HOST=$(get_config CLUSTER_NODE_HOST)
        if [ -z "$CLUSTER_NODE_HOST" ]; then
            CLUSTER_NODE_HOST=$(hostname)
        fi

        CLUSTER_NODE_IP=$(get_config CLUSTER_NODE_IP)
        if [ -z "$CLUSTER_NODE_IP" ]; then
            CLUSTER_NODE_IP=$(create_cluster_ip)
        fi

        CLUSTER_NODE_PORT=$(get_config CLUSTER_NODE_PORT)
        if [ -z "$CLUSTER_NODE_PORT" ]; then
            CLUSTER_NODE_PORT=54321
        fi

        CLUSTER_NODE_PRIVATE_KEY=$(get_config CLUSTER_NODE_PRIVATE_KEY)
        if [ -z "$CLUSTER_NODE_PRIVATE_KEY" ]; then
            CLUSTER_NODE_PRIVATE_KEY=$(create_cluster_private_key)
        fi
        CLUSTER_NODE_PUBLIC_KEY=$(get_config CLUSTER_NODE_PUBLIC_KEY)
        if [ -z "$CLUSTER_NODE_PUBLIC_KEY" ]; then
            CLUSTER_NODE_PUBLIC_KEY=$(create_cluster_public_key "$CLUSTER_NODE_PRIVATE_KEY")
        fi

        CLUSTER_NODE_IPW=$(get_config CLUSTER_NODE_IPW)
        if [ -z "$CLUSTER_NODE_IPW" ]; then
            CLUSTER_NODE_IPW=$(create_cluster_ip)
            # check if same
            if [ "$CLUSTER_NODE_IP" = "$CLUSTER_NODE_IPW" ]; then
                CLUSTER_NODE_IPW=$(create_cluster_ip)
            fi
        fi

        CLUSTER_NODE_PORTW=$(get_config CLUSTER_NODE_PORTW)
        if [ -z "$CLUSTER_NODE_PORTW" ]; then
            CLUSTER_NODE_PORTW=54320
        fi

        CLUSTER_NODE_PEERS=$(get_config CLUSTER_NODE_PEERS)
        if [ -z "$CLUSTER_NODE_PEERS" ]; then
            CLUSTER_NODE_PEERS=""
        fi
        CLUSTER_REDIS_MASTER=$(get_config CLUSTER_REDIS_MASTER)
        CLUSTER_REDIS_QUORUM=$(get_config CLUSTER_REDIS_QUORUM)
        if [ -z "$CLUSTER_REDIS_QUORUM" ]; then
            CLUSTER_REDIS_QUORUM=2
        fi

        CLUSTER_REDIS_INTEL_MASTER=$(get_config CLUSTER_REDIS_INTEL_MASTER)
        CLUSTER_REDIS_INTEL_QUORUM=$(get_config CLUSTER_REDIS_INTEL_QUORUM)
        if [ -z "$CLUSTER_REDIS_INTEL_QUORUM" ]; then
            CLUSTER_REDIS_INTEL_QUORUM=2
        fi

        CLUSTER_ES_PEERS=$(get_config CLUSTER_ES_PEERS)
        if [ -z "$CLUSTER_ES_PEERS" ]; then
            CLUSTER_ES_PEERS=""
        fi

        CLUSTER_NODE_PUBLIC_IP=$(get_config CLUSTER_NODE_PUBLIC_IP)
        if [ -z "$CLUSTER_NODE_PUBLIC_IP" ]; then
            CLUSTER_NODE_PUBLIC_IP=""
        fi

        CLUSTER_NODE_PUBLIC_PORT=$(get_config CLUSTER_NODE_PUBLIC_PORT)
        if [ -z "$CLUSTER_NODE_PUBLIC_PORT" ]; then
            CLUSTER_NODE_PUBLIC_PORT=""
        fi

        CLUSTER_NODE_PUBLIC_IPW=$(get_config CLUSTER_NODE_PUBLIC_IPW)
        if [ -z "$CLUSTER_NODE_PUBLIC_IPW" ]; then
            CLUSTER_NODE_PUBLIC_IPW=""
        fi

        CLUSTER_NODE_PUBLIC_PORTW=$(get_config CLUSTER_NODE_PUBLIC_PORTW)
        if [ -z "$CLUSTER_NODE_PUBLIC_PORTW" ]; then
            CLUSTER_NODE_PUBLIC_PORTW=""
        fi

        CLUSTER_NODE_PEERSW=$(get_config CLUSTER_NODE_PEERSW)
        if [ -z "$CLUSTER_NODE_PEERSW" ]; then
            CLUSTER_NODE_PEERSW=""
        fi

        FERRUM_CLOUD_ID=$(get_config FERRUM_CLOUD_ID)
        if [ -z "$FERRUM_CLOUD_ID" ]; then
            FERRUM_CLOUD_ID=""
        fi

        FERRUM_CLOUD_URL=$(get_config FERRUM_CLOUD_URL)
        if [ -z "$FERRUM_CLOUD_URL" ]; then
            FERRUM_CLOUD_URL=""
        fi

        FERRUM_CLOUD_TOKEN=$(get_config FERRUM_CLOUD_TOKEN)
        if [ -z "$FERRUM_CLOUD_TOKEN" ]; then
            FERRUM_CLOUD_TOKEN=""
        fi

        FERRUM_CLOUD_IP=$(get_config FERRUM_CLOUD_IP)
        if [ -z "$FERRUM_CLOUD_IP" ]; then
            FERRUM_CLOUD_IP=""
        fi

        FERRUM_CLOUD_PORT=$(get_config FERRUM_CLOUD_PORT)
        if [ -z "$FERRUM_CLOUD_PORT" ]; then
            FERRUM_CLOUD_PORT=""
        fi

        #SSL_FILE=$(create_certificates)
        #SSL_PUB=$(cat ${SSL_FILE}.crt | base64 -w 0)
        #SSL_KEY=$(cat ${SSL_FILE}.key | base64 -w 0)
        #rm ${SSL_FILE}.crt && rm ${SSL_FILE}.key

        ENV_FILE_ETC="$ETC_DIR/env"

        ## check installed
        allready_installed=N
        if [ -f $ENV_FILE_ETC ]; then
            allready_installed=Y
            # make backup
            BACKUP_FOLDER="$ETC_DIR/backup/$(date +%Y-%m-%d-%H-%M-%S)"
            rm -rf "$BACKUP_FOLDER"
            mkdir -p "$BACKUP_FOLDER"
            for file in $(ls $ETC_DIR | grep -v -e backup); do
                if [ "$file" != "backup" ]; then
                    cp -r "$ETC_DIR/$file" "$BACKUP_FOLDER"
                    info backup "$file"
                fi
            done
            if [ -f /usr/local/bin/ferrumgate ]; then
                cp /usr/local/bin/ferrumgate "$BACKUP_FOLDER"
            fi

        fi

        cat >$ENV_FILE_ETC <<EOF
DEPLOY=docker
ROLES=$ROLES
DEPLOY_ID=$DEPLOY_ID
NODE_ID=$NODE_ID
VERSION=$VERSION
REDIS_HOST=$REDIS_HOST
REDIS_HA_HOST=$REDIS_HA_HOST
REDIS_HOST_SSH=$REDIS_HOST_SSH
REDIS_PROXY_HOST=
REDIS_PASS=$REDIS_PASS
REDIS_LOCAL_HOST=$REDIS_LOCAL_HOST
REDIS_LOCAL_PASS=$REDIS_LOCAL_PASS
REDIS_INTEL_HOST=$REDIS_INTEL_HOST
REDIS_INTEL_HA_HOST=$REDIS_INTEL_HA_HOST
REDIS_INTEL_PROXY_HOST=
REDIS_INTEL_PASS=$REDIS_INTEL_PASS
ENCRYPT_KEY=$ENCRYPT_KEY
ES_HOST=$ES_HOST
ES_HA_HOST=$ES_HA_HOST
ES_USER=$ES_USER
ES_PASS=$ES_PASS
ES_PROXY_HOST=
ES_INTEL_HOST=$ES_INTEL_HOST
ES_INTEL_USER=$ES_INTEL_USER
ES_INTEL_PASS=$ES_INTEL_PASS
LOG_LEVEL=$LOG_LEVEL
REST_HTTP_PORT=$REST_HTTP_PORT
REST_HTTPS_PORT=$REST_HTTPS_PORT
LOG_REPLICAS=$LOG_REPLICAS
LOG_PARSER_REPLICAS=$LOG_PARSER_REPLICAS
CLUSTER_NODE_HOST=$CLUSTER_NODE_HOST
CLUSTER_NODE_IP=$CLUSTER_NODE_IP
CLUSTER_NODE_PORT=$CLUSTER_NODE_PORT
CLUSTER_NODE_PRIVATE_KEY=$CLUSTER_NODE_PRIVATE_KEY
CLUSTER_NODE_PUBLIC_KEY=$CLUSTER_NODE_PUBLIC_KEY
CLUSTER_NODE_PEERS=$CLUSTER_NODE_PEERS
CLUSTER_REDIS_MASTER=$CLUSTER_REDIS_MASTER
CLUSTER_REDIS_QUORUM=$CLUSTER_REDIS_QUORUM
CLUSTER_REDIS_INTEL_MASTER=$CLUSTER_REDIS_INTEL_MASTER
CLUSTER_REDIS_INTEL_QUORUM=$CLUSTER_REDIS_INTEL_QUORUM
CLUSTER_ES_PEERS=$CLUSTER_ES_PEERS
CLUSTER_NODE_PUBLIC_IP=$CLUSTER_NODE_PUBLIC_IP
CLUSTER_NODE_PUBLIC_PORT=$CLUSTER_NODE_PUBLIC_PORT
CLUSTER_NODE_IPW=$CLUSTER_NODE_IPW
CLUSTER_NODE_PORTW=$CLUSTER_NODE_PORTW
CLUSTER_NODE_PUBLIC_IPW=$CLUSTER_NODE_PUBLIC_IPW
CLUSTER_NODE_PUBLIC_PORTW=$CLUSTER_NODE_PUBLIC_PORTW
CLUSTER_NODE_PEERSW=$CLUSTER_NODE_PEERSW
FERRUM_CLOUD_ID=$FERRUM_CLOUD_ID
FERRUM_CLOUD_URL=$FERRUM_CLOUD_URL
FERRUM_CLOUD_TOKEN=$FERRUM_CLOUD_TOKEN
FERRUM_CLOUD_IP=$FERRUM_CLOUD_IP
FERRUM_CLOUD_PORT=$FERRUM_CLOUD_PORT

EOF

        chmod 600 $ENV_FILE_ETC

        #copy base file
        DOCKER_BASE_FILE=docker.base.yaml
        cp $DOCKER_BASE_FILE compose.yaml

        DOCKER_FILE=compose.yaml

        if [ $ENV_FOR != "PROD" ]; then # for test use local private registry

            sed -i 's#??PRIVATE_REGISTRY/#registry.ferrumgate.zero/#g' $DOCKER_FILE
        else
            sed -i 's#??PRIVATE_REGISTRY/##g' $DOCKER_FILE

        fi

        DOCKER_FILE_BASE_ETC=$ETC_DIR/base.yaml
        cp -f $DOCKER_FILE $DOCKER_FILE_BASE_ETC

        chmod 600 $DOCKER_FILE_BASE_ETC

        # copy gateway sample
        DOCKER_GATEWAY_FILE=docker.gateway.yaml
        cp $DOCKER_GATEWAY_FILE compose.yaml

        DOCKER_FILE=compose.yaml

        if [ $ENV_FOR != "PROD" ]; then # for test use local private registry

            sed -i 's#??PRIVATE_REGISTRY/#registry.ferrumgate.zero/#g' $DOCKER_FILE
        else
            sed -i 's#??PRIVATE_REGISTRY/##g' $DOCKER_FILE

        fi

        DOCKER_FILE_ETC=$ETC_DIR/gateway.yaml
        cp -f $DOCKER_FILE $DOCKER_FILE_ETC
        chmod 600 $DOCKER_FILE_ETC

        if [ $allready_installed = N ]; then

            sed -i "s/??GATEWAY_ID/$GATEWAY_ID/g" $DOCKER_FILE
            sed -i 's/??SSH_PORT/9999/g' $DOCKER_FILE

            DOCKER_FILE_GATEWAY_ETC="$ETC_DIR/gateway.$GATEWAY_ID.yaml"
            cp -f "$DOCKER_FILE" "$DOCKER_FILE_GATEWAY_ETC"
            chmod 600 "$DOCKER_FILE_GATEWAY_ETC"
        else
            info "updating installed version"
            for file in "$$ETC_DIR"/*; do
                result=$(is_gateway_yaml "$file")
                if [ ! -z "$result" ]; then
                    local gateway_id=$(echo "$file" | sed -e "s/gateway.//" -e "s/.yaml//")
                    local ssh_port=$(cat "$ETC_DIR/$file" | grep ":9999" | head -n 1 | sed -e "s/-//g" | sed -e "s/ //g" | sed -e "s/\"//g" | cut -d":" -f1)
                    cp "$ETC_DIR/gateway.yaml" "$ETC_DIR/$file"
                    sed -i "s/??GATEWAY_ID/$gateway_id/g" "$ETC_DIR/$file"
                    sed -i "s/??SSH_PORT/$ssh_port/g" "$ETC_DIR/$file"
                    info "updated $file"

                fi
            done
        fi

        info "installing services"
        install_services

        info "copy script files"
        sed -i "s/??VERSION/$VERSION/g" sh/run/ferrumgate.sh
        cp sh/run/ferrumgate.sh /usr/local/bin/ferrumgate
        chmod +x /usr/local/bin/ferrumgate
        #docker node update --label-add Ferrum_Node=management $(hostname)

        if [ $ENV_FOR != "PROD" ]; then

            docker compose -f "$DOCKER_FILE_BASE_ETC" --env-file "$ENV_FILE_ETC" pull
            for file in "$$ETC_DIR"/*; do
                result=$(is_gateway_yaml "$file")
                if [ ! -z "$result" ]; then

                    docker compose -f "$ETC_DIR/$file" --env-file "$ENV_FILE_ETC" pull
                fi
            done
            ferrumgate --restart
        fi
        info "system is ready"

    fi
}

main "$@"
