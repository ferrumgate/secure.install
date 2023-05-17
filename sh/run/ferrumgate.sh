#!/bin/sh
TRUE=0
FALSE=1
MODE="single"

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
    echo "  ferrumgate [ -h | --help ]        -> prints help"
    echo "  ferrumgate [ -s | --start ]       -> start service"
    echo "  ferrumgate [ -x | --stop ]        -> stop service"
    echo "  ferrumgate [ -t | --status ]      -> show status"
    echo "  ferrumgate [ -u | --uninstall ]   -> uninstall"
    echo "  ferrumgate [ -l process | --logs process]   -> get logs of running process"
    echo "  process rest, log, admin, task, ssh"
    echo "  ferrumgate [ -c redis | --config redis ] -> get/set config with name"
    echo "  ferrumgate [ -m | --multi ] -> get/set working mode single or multi gateway"

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
status_service() {
    systemctl status ferrumgate
    info "for more execute docker ps"
}
WORKDIR=/etc/ferrumgate

start_gateways() {
    docker compose -f $WORKDIR/ferrumgate.docker.yaml --profile $MODE up -d --remove-orphans
}
stop_gateways() {
    docker compose -f $WORKDIR/ferrumgate.docker.yaml --profile $MODE down
}
SCRIPT=/usr/local/bin/ferrumgate
change_mode() {

    info "current mode is $MODE "
    read -p "do you want to change [Yn] " yesno
    if [ $yesno = "Y" ]; then
        read -p "enter single or multi : " mode
        if [ $mode = "multi" ]; then
            sed -i "s/^MODE=.*/MODE=multi/g" $SCRIPT
        else
            sed -i "s/^MODE=.*/MODE=single/g" $SCRIPT
        fi
    fi
}

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
logs() {
    local name=$1
    docker ps | grep ferrumgate | grep $name | cut -d' ' -f 1 | xargs docker logs -f
}
config() {
    local name=$1
    if [ name == "redis" ]; then
        local redis_host=$(cat /etc/ferrumgate/ferrumgate.docker.yaml | grep "REDIS_HOST")
        local redis_pass=$(cat /etc/ferrumgate/ferrumgate.docker.yaml | grep "REDIS_PASS")
        echo $redis_host
        echo $redis_pass
    fi

}

main() {
    ensure_root

    ARGS=$(getopt -o 'hsxtul:c:m' --long 'help,start,stop,status,uninstall,logs:config:,start-gateways,stop-gateways,mode' -- "$@") || exit
    eval "set -- $ARGS"
    local SERVICE_NAME=''
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
        -t | --status)
            opt=4
            shift
            break
            ;;
        -u | --uninstall)
            opt=5
            shift
            break
            ;;
        -l | --logs)
            opt=6
            SERVICE_NAME="$2"
            shift 2
            break
            ;;
        -c | --config)
            opt=7
            SERVICE_NAME="$2"
            shift 2
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
        -m | --mode)
            opt=10
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

    [ $opt -eq 1 ] && print_usage && exit 0
    [ $opt -eq 2 ] && start_service && exit 0
    [ $opt -eq 3 ] && stop_service && exit 0
    [ $opt -eq 4 ] && status_service && exit 0
    [ $opt -eq 5 ] && uninstall && exit 0
    [ $opt -eq 6 ] && logs $SERVICE_NAME && exit 0
    [ $opt -eq 7 ] && config $SERVICE_NAME && exit 0
    [ $opt -eq 8 ] && start_gateways && exit 0
    [ $opt -eq 9 ] && stop_gateways && exit 0
    [ $opt -eq 10 ] && change_mode && exit 0

}

main $*
