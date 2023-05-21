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
    echo "  ferrumgate [ -c | --config ] redis,mode -> get/set config with name"
    echo "  ferrumgate [ -l | --logs ] process -> get logs of running process"
    echo "  logs process rest, log, admin, task, ssh"

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

ETCDIR=/etc/ferrumgate

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
find_default_gateway() {
    for file in $(ls $ETCDIR); do
        if [[ $file = *.env ]]; then

            local gatewayId=$(echo "$file" | sed -e "s/ferrumgate.//" -e "s/.env//")
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

    docker ps | grep ferrumgate-$gateway_id | grep $service | cut -d" " -f1 | xargs -r docker logs -f
}

get_mode() {
    if [ $# -lt 1 ]; then
        error "no arguments supplied"
        exit 1
    fi
    local file=ferrumgate.$1.env
    mode=$(cat $ETCDIR/$file | grep MODE= | cut -d'=' -f2)
    echo $mode
}

list_gateways() {
    for file in $(ls $ETCDIR); do
        if [[ $file = *.env ]]; then

            local gatewayId=$(echo "$file" | sed -e "s/ferrumgate.//" -e "s/.env//")
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
    rm -rf $ETCDIR/ferrumgate.$gateway_id.yaml
    rm -rf $ETCDIR/ferrumgate.$gateway_id.env
    docker network ls | grep $gateway_id | tr -s ' ' | cut -d' ' -f2 | xargs -r docker network rm
    docker volume ls | grep $gateway_id | tr -s ' ' | cut -d' ' -f2 | xargs -r docker volume rm

}

start_gateway() {
    if [ $# -lt 1 ]; then
        error "no arguments supplied"
        exit 1
    fi

    local gatewayId=$1
    local mode=$(get_mode $1)
    docker compose -f $ETCDIR/ferrumgate.$gatewayId.yaml --env-file $ETCDIR/ferrumgate.$gatewayId.env \
        -p ferrumgate-$gatewayId --profile $mode up -d --remove-orphans
}

start_gateways() {

    for file in $(ls $ETCDIR); do
        if [[ $file = *.env ]]; then
            local gatewayId=$(echo "$file" | sed -e "s/ferrumgate.//" -e "s/.env//")
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
    local mode=$(get_mode $gatewayId)
    docker compose -f $ETCDIR/ferrumgate.$gatewayId.yaml --env-file $ETCDIR/ferrumgate.$gatewayId.env \
        -p ferrumgate-$gatewayId --profile $mode down
}

stop_gateways() {

    for file in $(ls $ETCDIR); do
        if [[ $file = *.env ]]; then

            local gatewayId=$(echo "$file" | sed -e "s/ferrumgate.//" -e "s/.env//")
            stop_gateway $gatewayId
        fi
    done

}

set_config_gateway() {
    if [ $# -lt 3 ]; then
        error "no arguments supplied"
        exit 1
    fi
    local gatewayId=$1
    local key=$2
    local value=$3
    file=$ETCDIR/ferrumgate.$gatewayId.env
    sed -i "s/^$key=.*/$key=$value/g" $file

}
get_config_gateway() {
    if [ $# -lt 2 ]; then
        error "no arguments supplied"
        exit 1
    fi
    local gatewayId=$1
    local key=$2

    file=$ETCDIR/ferrumgate.$gatewayId.env
    value=$(cat $file | grep $key= | cut -d" " -f2)
    echo $value
}

config_gateway() {
    if [ $# -lt 2 ]; then
        error "no arguments supplied"
        exit 1
    fi
    local gatewayId=$1
    local param=$2
    if [ $param = "mode" ]; then

        mode=$(get_mode $gatewayId)
        info "current mode is $mode "
        read -p "do you want to change [Yn] " yesno
        if [ $yesno = "Y" ]; then
            read -p "enter single or cluster : " mode
            if [ $mode = "cluster" ]; then
                set_config_gateway $gatewayId MODE cluster
            else
                set_config_gateway $gatewayId MODE single
            fi
        fi
    fi
    if [ $param = "redis" ]; then

        mode=$(get_mode $gatewayId)
        info "current mode is $mode "
        redis=$(get_config_gateway $gatewayId REDIS_HOST)
        redis_pass=$(get_config_gateway $gatewayId REDIS_PASS)
        echo redis:$redis
        echo pass:$redis_pass
        read -p "do you want to change [Yn] " yesno
        if [ $yesno = "Y" ]; then
            read -p "enter host : " host
            set_config_gateway $gatewayId REDIS_HOST $host
            read -p "enter pass : " pass
            set_config_gateway $gatewayId REDIS_PASS $pass
            if [ $host = "redis" ]; then
                set_config_gateway $gatewayId MODE single
            else
                set_config_gateway $gatewayId MODE cluster
            fi

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
    config:\' -- "$@") || exit
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
        -c | --config)
            opt=14
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
    [ $opt -eq 14 ] && config_gateway $gateway_id $parameter_name && exit 0

}

main $*
