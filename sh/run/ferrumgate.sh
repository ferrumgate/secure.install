#!/bin/sh
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

print_usage() {
    echo "usage"
    echo "  ferrumgate [ -h | --help ]        -> prints help"
    echo "  ferrumgate [ -s | --start ]       -> start service"
    echo "  ferrumgate [ -x | --stop ]        -> stop service"
    echo "  ferrumgate [ -l | --status ]      -> show status"
    echo "  ferrumgate [ -u | --uninstall ]   -> uninstall"

}

start_service() {

    systemctl start ferrumgate
    info "ferrumgate started"
    info "for more execute docker ps"
}
stop_service() {
    systemctl stop ferrumgate
    info "ferrumgate stopped"
    info "for more execute docker ps"

}
status_service() {
    systemctl status ferrumgate
    info "for more execute docker ps"
}
uninstall() {
    read -p "are you sure [Yn] " yesno
    if [ $yesno = "Y" ]; then

        info "uninstall started"
        systemctl stop ferrumgate
        systemctl disable ferrumgate
        ## force
        docker ps | grep ferrumgate | tr -s ' ' | cut -d' ' -f 1 | xargs docker stop
        ## rm service
        rm /etc/systemd/system/ferrumgate.service
        ## rm folder
        rm -rf /etc/ferrumgate
        ## rm docker related
        docker network ls | grep ferrum | tr -s ' ' | cut -d' ' -f2 | xargs docker network rm
        docker volume ls | grep ferrumgate | tr -s ' ' | cut -d' ' -f2 | xargs docker volume rm
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

main() {
    ensure_root

    ARGS=$(getopt -o 'hsxlu' --long 'help,start,stop,status,uninstall' -- "$@") || exit
    eval "set -- $ARGS"
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
        -l | --status)
            opt=4
            shift
            break
            ;;
        -u | --uninstall)
            opt=5
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

}

main $*
