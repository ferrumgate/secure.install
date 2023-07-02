#!/bin/bash
TRUE=0
FALSE=1

### log functions

info() {
    echo '[INFO] ' "$@"
}
error() {
    echo '[ERROR] ' "$@" >&2
}
warn() {
    echo '[WARN] ' "$@" >&2
}
fatal() {
    echo '[FATAL] ' "$@" >&2
    exit 1
}
debug() {
    if [ $ENV_FOR != "PROD" ]; then
        echo '[INFO] ' "$@"
    fi
}

#### add quotes to command arguments
quote() {
    for arg in "$@"; do
        printf '%s\n' "$arg" | sed "s/'/'\\\\''/g;1s/^/'/;\$s/\$/'/"
    done
}

#### add indentation and trailing slash to quoted args
quote_indent() {
    printf ' \\\n'
    for arg in "$@"; do
        printf '\t%s \\\n' "$(quote "$arg")"
    done
}

#### escape most punctuation characters, except quotes, forward slash, and space
escape() {
    printf '%s' "$@" | sed -e 's/\([][!#$%&()*;<=>?\_`{|}]\)/\\\1/g;'
}

#### escape double quotes
escape_dq() {
    printf '%s' "$@" | sed -e 's/"/\\"/g'
}

VERSION=??VERSION

print_usage() {
    echo "usage:"
    echo "version: ${VERSION}"
    echo "  ferrumgate [ -h | --help ]         -> prints help"
    echo "  ferrumgate [ -s | --start ]        -> start service"
    echo "  ferrumgate [ -x | --stop ]         -> stop service"
    echo "  ferrumgate [ -r | --restart ]      -> restart service"
    echo "  ferrumgate [ -t | --status ]       -> show status"
    echo "  ferrumgate [ -u | --uninstall ]    -> uninstall"
    echo "  ferrumgate [ -c | --config ] redis -> get/set config with name, redis"
    echo "  ferrumgate [ -l | --logs ] process -> get logs of process rest,log, parser, admin, task, ssh"
    echo "  ferrumgate [ --list-gateways ]     -> list gateways"
    echo "  ferrumgate [ --start-gateway ] 4s3a92dd023 -> start a gateway"
    echo "  ferrumgate [ --stop-gateway ] 4s3a92dd023 -> stop a gateway"
    echo "  ferrumgate [ --delete-gateway ] 4s3a92dd023  -> delete a gateway"
    echo "  ferrumgate [ --create-gateway ] -> creates a new gateway"
    echo "  ferrumgate [ --recreate-gateway ] -> recreates a gateway"

}

start_service() {

    systemctl start ferrumgate
    info "ferrumgate started"
    info "for more execute docker ps"
}
stop_service() {
    systemctl stop ferrumgate
    docker ps | grep ferrumgate | tr -s ' ' | cut -d' ' -f 1 | xargs -r docker stop
    info "ferrumgate stopped"
    info "for more execute docker ps"

}
restart_service() {
    stop_service
    start_service

}
status_service() {
    systemctl status ferrumgate
    info "for more execute docker ps"
}

ETC_DIR=/etc/ferrumgate

uninstall() {
    read -p "are you sure [Yn] " yesno
    if [ $yesno = "Y" ]; then

        info "uninstall started"
        systemctl stop ferrumgate
        systemctl disable ferrumgate
        ## force
        docker ps | grep ferrumgate | tr -s ' ' | cut -d' ' -f 1 | xargs -r docker stop
        ## rm service
        rm /etc/systemd/system/ferrumgate.service
        ## rm folder
        rm -rf /etc/ferrumgate
        ## rm docker related
        docker network ls | grep ferrum | tr -s ' ' | cut -d' ' -f2 | xargs -r docker network rm
        docker volume ls | grep ferrumgate | tr -s ' ' | cut -d' ' -f2 | xargs -r docker volume rm
        ## rm this file
        rm /usr/local/bin/ferrumgate
        info "uninstall finished successfully"
    fi
}
ensure_root() {
    WUSER=$(id -u)
    if [ ! "$WUSER" -eq 0 ]; then
        echo "root privilges need"
        exit 1
    fi

}
is_gateway_yaml() {
    result=$(echo $1 | grep -E "gateway\.\w+\.yaml" || true)
    echo $result
}

find_default_gateway() {
    for file in $(ls $ETC_DIR); do
        local result=$(is_gateway_yaml $file)
        if [ ! -z $result ]; then
            local gatewayId=$(echo "$file" | sed -e "s/gateway.//" -e "s/.yaml//")
            echo $gatewayId
            break
        fi
    done
}
logs() {
    if [ $# -lt 2 ]; then
        error "need 2 arguments"
        exit 1
    fi
    local service=$2
    local gateway_id=$1
    local grepname=fg-$gateway_id

    if [ $service = "rest" ]; then
        grepname=fg-base
        service="rest.portal"
    fi
    if [ $service = "redis" ]; then
        grepname=fg-base
    fi
    if [ $service = "es" ]; then
        grepname=fg-base
    fi
    if [ $service = "task" ]; then
        grepname=fg-base
        service="task"
    fi
    if [ $service = "log" ]; then
        grepname=fg-base
    fi
    if [ $service = "parser" ]; then
        grepname=fg-base
    fi

    if [ $service = "ssh" ]; then
        service="server.ssh"
    fi
    if [ $service = "admin" ]; then
        service="job.admin"
    fi

    docker ps | grep $grepname | grep $service | cut -d" " -f1 | head -n1 | xargs -r docker logs -f
}

list_gateways() {
    for file in $(ls $ETC_DIR); do
        local result=$(is_gateway_yaml $file)
        if [ ! -z $result ]; then

            local gatewayId=$(echo "$file" | sed -e "s/gateway.//" -e "s/.yaml//")

            info $gatewayId

        fi
    done
}
delete_gateway() {
    if [ $# -lt 1 ]; then
        error "no arguments supplied"
        exit 1
    fi
    local gateway_id=$1
    stop_gateway $gateway_id
    rm -rf $ETC_DIR/gateway.$gateway_id.yaml
    docker network ls | grep $gateway_id | tr -s ' ' | cut -d' ' -f2 | xargs -r docker network rm
    docker volume ls | grep $gateway_id | tr -s ' ' | cut -d' ' -f2 | xargs -r docker volume rm

}

create_gateway() {
    local port=$1
    local gateway_id=$2
    if [ -z "$port" ]; then
        read -p "enter a port for ssh tunnel server: " p1
        port=$p1
    fi
    ## this must be lowercase , we are using with docker compose -p

    if [ -z $gateway_id ]; then
        gateway_id=$(cat /dev/urandom | tr -dc '[:alnum:]' | fold -w 16 | head -n 1 | tr '[:upper:]' '[:lower:]')
    fi
    DOCKER_FILE=$ETC_DIR/gateway.$gateway_id.yaml
    rm -rf $DOCKER_FILE
    cp $ETC_DIR/gateway.yaml $DOCKER_FILE
    sed -i "s/??GATEWAY_ID/$gateway_id/g" $DOCKER_FILE
    sed -i "s/??SSH_PORT/$port/g" $DOCKER_FILE
    info "created gateway $gateway_id  at port $port"
    info "start gateway"
}

recreate_gateway() {
    read -p "enter a port for ssh tunnel server: " port
    ## this must be lowercase , we are using with docker compose -p
    read -p "enter gateway id:" gateway_id
    create_gateway $port $gateway_id
}

start_base() {
    info "starting base"
    docker compose -f $ETC_DIR/base.yaml --env-file $ETC_DIR/env \
        -p fg-base up -d --remove-orphans
}
stop_base() {
    info "stoping base"
    docker compose -f $ETC_DIR/base.yaml --env-file $ETC_DIR/env \
        -p fg-base down
}

start_gateway() {
    if [ $# -lt 1 ]; then
        error "no arguments supplied"
        exit 1
    fi

    local gatewayId=$1
    info "starting gateway $gatewayId"
    docker compose -f $ETC_DIR/gateway.$gatewayId.yaml --env-file $ETC_DIR/env \
        -p fg-$gatewayId up -d --remove-orphans
}

start_gateways() {
    start_base
    for file in $(ls $ETC_DIR); do
        local result=$(is_gateway_yaml $file)
        if [ ! -z $result ]; then
            local gatewayId=$(echo "$file" | sed -e "s/gateway.//" -e "s/.yaml//")
            start_gateway $gatewayId
        fi
    done

}
stop_gateway() {

    if [ $# -lt 1 ]; then
        error "no arguments supplied"
        exit 1
    fi

    local gatewayId=$1
    info "stoping gateway $gatewayId"
    docker compose -f $ETC_DIR/gateway.$gatewayId.yaml --env-file $ETC_DIR/env \
        -p fg-$gatewayId down
}

stop_gateways() {

    for file in $(ls $ETC_DIR); do
        local result=$(is_gateway_yaml $file)
        if [ ! -z $result ]; then

            local gatewayId=$(echo "$file" | sed -e "s/gateway.//" -e "s/.yaml//")
            stop_gateway $gatewayId
        fi
    done
    stop_base

}

set_config() {
    if [ $# -lt 2 ]; then
        error "no arguments supplied"
        exit 1
    fi
    local key=$1
    local value=$2
    file=$ETC_DIR/env
    sed -i "s/^$key=.*/$key=$value/g" $file

}
get_config() {
    if [ $# -lt 1 ]; then
        error "no arguments supplied"
        exit 1
    fi

    local key=$1

    file=$ETC_DIR/env
    value=$(cat $file | grep $key= | cut -d" " -f2)
    echo $value
}

config() {
    if [ $# -lt 1 ]; then
        error "no arguments supplied"
        exit 1
    fi

    local param=$1

    if [ $param = "redis" ]; then

        redis=$(get_config REDIS_HOST)
        redis_pass=$(get_config REDIS_PASS)
        echo $redis
        echo $redis_pass
        read -p "do you want to change [Yn] " yesno
        if [ $yesno = "y" ]; then
            read -p "enter host : " host
            read -p "enter pass : " pass

            set_config REDIS_HOST $host
            redis_host_ssh=$(echo $host | sed 's/:/#/g')
            set_config REDIS_HOST_SSH $redis_host_ssh
            set_config REDIS_PASS $pass

            if [ $host = "redis:6379" ]; then
                set_config MODE single
            else
                set_config MODE cluster
            fi
            info "please restart ferrumgate"

        fi
    fi

}

main() {
    ensure_root

    ARGS=$(getopt -o 'hsxrtul:c:g:' --long '\
    help,start,stop,restart,status,uninstall,\
    logs:,\
    gateway:,\
    start-gateways,\
    stop-gateways,\
    list-gateways,\
    start-gateway:,\
    stop-gateway:,\
    delete-gateway:,\
    create-gateway,\
    recreate-gateway,\
    config:' -- "$@") || exit
    eval "set -- $ARGS"
    local service_name=''
    local gateway_id=''
    local parameter_name=''
    local opt=1
    while true; do
        case $1 in
        -h | --help)
            opt=1
            shift
            break
            ;;
        -s | --start)
            opt=2
            shift
            break
            ;;
        -x | --stop)
            opt=3
            shift
            break
            ;;
        -r | --restart)
            opt=4
            shift
            break
            ;;
        -t | --status)
            opt=5
            shift
            break
            ;;
        -g | --gateway)
            gateway_id="$2"
            shift 2
            ;;
        -l | --logs)
            opt=6
            service_name="$2"
            shift 3
            break
            ;;
        -u | --uninstall)
            opt=7
            shift
            break
            ;;
        --start-gateways)
            opt=8
            shift
            break
            ;;
        --stop-gateways)
            opt=9
            shift
            break
            ;;
        --list-gateways)
            opt=10
            shift
            break
            ;;
        --start-gateway)
            opt=11
            gateway_id="$2"
            shift 2
            break
            ;;
        --stop-gateway)
            opt=12
            gateway_id="$2"
            shift 2
            break
            ;;
        --delete-gateway)
            opt=13
            gateway_id="$2"
            shift 2
            break
            ;;
        --create-gateway)
            opt=14
            shift
            break
            ;;
        --recreate-gateway)
            opt=15
            shift
            break
            ;;
        -c | --config)
            opt=16
            parameter_name="$2"
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

    if [ -z $gateway_id ]; then
        gateway_id=$(find_default_gateway)
    fi

    [ $opt -eq 1 ] && print_usage && exit 0
    [ $opt -eq 2 ] && start_service && exit 0
    [ $opt -eq 3 ] && stop_service && exit 0
    [ $opt -eq 4 ] && restart_service && exit 0
    [ $opt -eq 5 ] && status_service && exit 0
    [ $opt -eq 6 ] && logs $gateway_id $service_name && exit 0
    [ $opt -eq 7 ] && uninstall && exit 0
    [ $opt -eq 8 ] && start_gateways && exit 0
    [ $opt -eq 9 ] && stop_gateways && exit 0
    [ $opt -eq 10 ] && list_gateways && exit 0
    [ $opt -eq 11 ] && start_gateway $gateway_id && exit 0
    [ $opt -eq 12 ] && stop_gateway $gateway_id && exit 0
    [ $opt -eq 13 ] && delete_gateway $gateway_id && exit 0
    [ $opt -eq 14 ] && create_gateway && exit 0
    [ $opt -eq 15 ] && recreate_gateway && exit 0
    [ $opt -eq 16 ] && config $parameter_name && exit 0

}

main $*
