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
    echo "  ferrumgate [ --help ]         -> prints help"
    echo "  ferrumgate [ --start ]        -> start service"
    echo "  ferrumgate [ --stop ]         -> stop service"
    echo "  ferrumgate [ --restart ]      -> restart service"
    echo "  ferrumgate [ --status ]       -> show status"
    echo "  ferrumgate [ --uninstall ]    -> uninstall"
    echo "  ferrumgate [ --set-config ] [redis,es,...] -> set config with name, redis"
    echo "  ferrumgate [ --show-config ] [var name] -> get config with name"
    echo "  ferrumgate [ --logs ] process -> get logs of process rest,log, parser, admin, task, ssh"
    echo "  ferrumgate [ --list-gateways ]-> list gateways"
    echo "  ferrumgate [ --start-gateway ] gatewayId -> start a gateway"
    echo "  ferrumgate [ --stop-gateway ] gatewayId -> stop a gateway"
    echo "  ferrumgate [ --delete-gateway ] gatewayId  -> delete a gateway"
    echo "  ferrumgate [ --create-gateway ] -> creates a new gateway"
    echo "  ferrumgate [ --recreate-gateway ] -> recreates a gateway"
    echo "  ferrumgate [ --start-cluster ] -> starts cluster"
    echo "  ferrumgate [ --stop-cluster ] -> stop cluster"
    echo "  ferrumgate [ --status-cluster ] -> cluster status"
    echo "  ferrumgate [ --recreate-cluster-keys ] -> recreate cluster keys"
    echo "  ferrumgate [ --show-cluster-config ] -> show cluster config"
    echo "  ferrumgate [ --add-cluster-peer ] peerVariable -> add a peer to cluster"
    echo "  ferrumgate [ --remove-cluster-peer ] peername -> remove peer from cluster"
    echo "  ferrumgate [ --set-cluster-config ] -> change cluster config"
    echo "  ferrumgate [ --set-redis-master ] -> change cluster config"
    echo "  ferrumgate [ --remove-redis-master ] -> change cluster config"
    echo "  ferrumgate [ --show-es-peers ] -> shows es peers"
    echo "  ferrumgate [ --add-es-peer ] peerVariable -> add a peer to es ha"
    echo "  ferrumgate [ --remove-es-peer ] peername -> remove a peer from es ha"
    echo "  ferrumgate [ --all-logs ] shows all logs"

}

start_service() {

    #systemctl start ferrumgate
    start_gateways
    info "ferrumgate started"
    info "for more execute docker ps"
}

stop_service() {

    #systemctl stop ferrumgate
    stop_gateways
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
    info "created gateway $gateway_id at port $port"
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
prepare_env() {
    local redis_host=$(get_config REDIS_HOST)
    local redis_ha_host=$(get_config REDIS_HA_HOST)
    local is_redis_clustered=$(get_config CLUSTER_REDIS_MASTER)
    if [ -z "$is_redis_clustered" ]; then
        info "redis is not clustered"
        set_config REDIS_PROXY_HOST $redis_host
        local redis_host_ssh=$(echo $redis_host | sed 's/:/#/g')
        set_config REDIS_HOST_SSH $redis_host_ssh
    else
        info "redis is clustered"
        set_config REDIS_PROXY_HOST $redis_ha_host
        local redis_host_ssh=$(echo $redis_ha_host | sed 's/:/#/g')
        set_config REDIS_HOST_SSH $redis_host_ssh

    fi

    local es_host=$(get_config ES_HOST)
    local es_ha_host=$(get_config ES_HA_HOST)
    local is_es_clustered=$(get_config CLUSTER_ES_PEERS)
    if [ -z "$is_es_clustered" ]; then
        set_config ES_PROXY_HOST $es_host
    else
        set_config ES_PROXY_HOST $es_ha_host
    fi
}

start_gateways() {
    prepare_env

    if [ -z $(is_cluster_working) ]; then
        start_cluster
    fi
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
    stop_cluster

}

set_config() {
    if [ $# -lt 2 ]; then
        error "no arguments supplied"
        exit 1
    fi
    local key=$1
    local value=$2
    file=$ETC_DIR/env
    sed -i "s|^$key=.*|$key=$value|g" $file

}
get_config() {
    if [ $# -lt 1 ]; then
        error "no arguments supplied"
        exit 1
    fi

    local key=$1

    file=$ETC_DIR/env
    value=$(cat $file | grep $key= | cut -d"=" -f2-)
    echo $value
}

show_config() {
    get_config $1
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
        echo "host: $redis"
        echo "pass: $redis_pass"
        read -p "do you want to change [Yn] " yesno
        if [ $yesno = "Y" ]; then
            read -p "enter host : " host
            read -p "enter pass : " pass

            set_config REDIS_HOST $host
            redis_host_ssh=$(echo $host | sed 's/:/#/g')
            set_config REDIS_HOST_SSH $redis_host_ssh
            set_config REDIS_PASS $pass

            set_config REDIS_INTEL_HOST $host
            set_config REDIS_INTEL_PASS $pass

            if [ $host = "redis:6379" ]; then
                set_config MODE single
            else
                set_config MODE cluster
            fi
            info "please restart ferrumgate"

        fi
        return
    fi

    if [ $param = "es" ]; then

        es=$(get_config ES_HOST)
        es_pass=$(get_config ES_PASS)
        echo "host: $es"
        echo "pass: $es_pass"
        read -p "do you want to change [Yn] " yesno
        if [ $yesno = "Y" ]; then
            read -p "enter host : " host
            read -p "enter pass : " pass

            set_config ES_HOST $host
            set_config ES_PASS $pass

            set_config ES_INTEL_HOST $host
            set_config ES_INTEL_PASS $pass
            info "please restart ferrumgate"

        fi
        return
    fi

    value=$(get_config $param)
    echo "value: $value"
    read -p "do you want to change [Yn] " yesno
    if [ $yesno = "Y" ]; then
        read -p "enter value : " val
        set_config $param $val
    fi

}
all_logs() {
    docker ps -q | xargs -L 1 -P $(docker ps | wc -l) docker logs --since 30s -f
}

create_cluster_ip() {
    local random=$(shuf -i 1-254 -n1)
    echo "169.254.254.$random"
}

cluster_info() {
    local node_ip=$(get_config CLUSTER_NODE_IP)
    local node_port=$(get_config CLUSTER_NODE_PORT)
    local peers=$(get_config CLUSTER_NODE_PEERS)
    echo "Listening: $node_ip:$node_port"
    echo "Peers: $peers"
}
is_cluster_working() {
    local count=$(ip a | grep wgferrum | wc -l)
    if [ ! $count -eq "0" ]; then
        echo "running"
    fi
}

stop_cluster() {

    if [ -z $(is_cluster_working) ]; then
        return
    fi
    wg-quick down wgferrum 2>/dev/null || true
    ip link del dev wgferrum || true
    info "stoped cluster"
}

start_cluster() {
    stop_cluster
    local node_ip=$(get_config CLUSTER_NODE_IP)
    local node_port=$(get_config CLUSTER_NODE_PORT)
    local node_private_key=$(get_config CLUSTER_NODE_PRIVATE_KEY)
    local node_public_key=$(get_config CLUSTER_NODE_PUBLIC_KEY)
    local node_peers=$(get_config CLUSTER_NODE_PEERS)

    if [ -z "$node_ip" ]; then
        warn "cluster node ip is needed"
        return
    fi
    if [ -z "$node_port" ]; then
        warn "cluster node port is needed"
        return
    fi
    if [ -z "$node_private_key" ]; then
        warn "cluster node private key is needed"
        return
    fi
    if [ -z "$node_public_key" ]; then
        warn "cluster node public key is needed"
        return
    fi
    if [ -z "$node_peers" ]; then
        warn "cluster peers is needed"
        ip link add dev wgferrum type wireguard || true
        ip address add dev wgferrum $node_ip/32 || true
        ip link set up dev wgferrum || true
        return
    fi
    FILE=/etc/wireguard/wgferrum.conf
    echo "[Interface]" >$FILE
    echo "Address=$node_ip/32" >>$FILE
    echo "ListenPort=$node_port" >>$FILE
    echo "PrivateKey=$(echo $node_private_key | xxd -r -p | base64)" >>$FILE
    for line in $node_peers; do
        echo "[Peer]" >>$FILE
        echo "Endpoint=$(echo $line | cut -d'/' -f2)" >>$FILE
        echo "AllowedIPs=$(echo $line | cut -d'/' -f3)" >>$FILE
        echo "PublicKey=$(echo $line | cut -d'/' -f4 | xxd -r -p | base64)" >>$FILE
        echo ""
    done

    wg-quick up wgferrum
    #ip link add dev wgferrum type wireguard || true
    #wg set wgferrum listen-port $node_port private-key /path/to/private-key peer ABCDEF... allowed-ips 192.168.88.0/24 endpoint 209.202.254.14:8172
    info "started cluster"

}

status_cluster() {
    wg show
}
create_cluster_private_key() {
    wg genkey | base64 -d | xxd -p -c 256
}
create_cluster_public_key() {
    echo $1 | xxd -r -p | base64 | wg pubkey | base64 -d | xxd -p -c 256
}
recreate_cluster_keys() {
    local pri=$(create_cluster_private_key)
    local pub=$(create_cluster_public_key $pri)
    set_config CLUSTER_NODE_PRIVATE_KEY $pri
    set_config CLUSTER_NODE_PUBLIC_KEY $pub
    info "recreated keys"
}

show_cluster_info() {
    local node_host=$(get_config CLUSTER_NODE_HOST)
    local node_ip=$(get_config CLUSTER_NODE_IP)
    local node_port=$(get_config CLUSTER_NODE_PORT)
    local node_public_key=$(get_config CLUSTER_NODE_PUBLIC_KEY)
    local node_peers=$(get_config CLUSTER_NODE_PEERS)
    echo "**** current host *****"
    echo "host: $node_host"
    echo "ip: $node_ip"
    echo "port: $node_port"
    echo "pubKey: $node_public_key"
}

show_cluster_config() {
    local node_host=$(get_config CLUSTER_NODE_HOST)
    local node_ip=$(get_config CLUSTER_NODE_IP)
    local node_port=$(get_config CLUSTER_NODE_PORT)
    local node_public_key=$(get_config CLUSTER_NODE_PUBLIC_KEY)

    local node_peers=$(get_config CLUSTER_NODE_PEERS)
    echo ""
    echo "**** current peers *****"
    for line in $node_peers; do
        echo $line
    done
    local cluster_public_ip=$CLUSTER_PUBLIC_IP
    if [ -z "$cluster_public_ip" ]; then
        cluster_public_ip="public_ip"
    fi

    local cluster_public_port=$CLUSTER_PUBLIC_PORT
    if [ -z "$cluster_public_port" ]; then
        cluster_public_port="port"
    fi
    echo ""
    echo "**** current host *****"
    echo "host: $node_host"
    echo "ip: $node_ip"
    echo "port: $node_port"
    echo "pubKey: $node_public_key"
    echo ""
    echo "**** commands **********"
    echo "PEER=\"$node_host/$cluster_public_ip:$cluster_public_port/$node_ip/$node_public_key\""
    echo "ferrumgate --add-cluster-peer \$PEER"
    echo "wg set wgferrum peer $(echo $node_public_key | xxd -r -p | base64) allowed-ips $node_ip"
}

add_cluster_peer() {
    if [ $# -lt 1 ]; then
        error "no arguments supplied"
        exit 1
    fi

    local input=$1
    local node_peers=$(get_config CLUSTER_NODE_PEERS)
    local node_host=$(get_config CLUSTER_NODE_HOST)
    local node_ip=$(get_config CLUSTER_NODE_IP)
    local input_host=$(echo $input | cut -d'/' -f1)

    if [ $input_host = $node_host ]; then
        error "you can not add this host to peers"
        return
    fi
    local peer=""
    for line in $node_peers; do
        local host=$(echo $line | cut -d'/' -f1)
        if [ $host != $input_host ]; then
            peer="$peer $line"
        fi
    done
    peer="$peer $input"

    set_config CLUSTER_NODE_PEERS "$peer"
    info "added to peers"
}

remove_cluster_peer() {
    if [ $# -lt 1 ]; then
        error "no arguments supplied"
        exit 1
    fi

    local input=$1
    local node_peers=$(get_config CLUSTER_NODE_PEERS)
    local node_host=$(get_config CLUSTER_NODE_HOST)
    local node_ip=$(get_config CLUSTER_NODE_IP)
    local input_host=$(echo $input | cut -d'/' -f1)

    local peer=""
    for line in $node_peers; do
        local host=$(echo $line | cut -d'/' -f1)
        if [ $host != "$input_host" ]; then
            peer="$peer $line"
        fi
    done
    peer="$peer $input"

    set_config CLUSTER_NODE_PEERS "$peer"
    info "removed from peers"
}

set_cluster_config() {
    show_cluster_info
    echo "which option do you want to change?"
    read -p "type host, ip, port, key: " selection

    if [ $selection = "host" ]; then
        read -p "enter hostname: " hostname
        read -p "are you sure [Yn] " yesno
        if [ $yesno = "Y" ]; then
            set_config CLUSTER_NODE_HOST $hostname
            info "cluster host changed"
        fi
    fi
    if [ $selection = "ip" ]; then
        read -p "enter ip: " ip
        read -p "are you sure [Yn] " yesno
        if [ $yesno = "Y" ]; then
            set_config CLUSTER_NODE_IP $ip
            info "cluster ip changed"
        fi
    fi

    if [ $selection = "port" ]; then
        read -p "enter port: " port
        read -p "are you sure [Yn] " yesno
        if [ $yesno = "Y" ]; then
            set_config CLUSTER_NODE_PORT $port
            info "cluster port changed"
        fi
    fi

    if [ $selection = "key" ]; then
        read -p "are you sure [Yn] " yesno
        if [ $yesno = "Y" ]; then
            recreate_cluster_keys
            info "cluster keys changed"
        fi
    fi

}

set_redis_master() {
    echo "current master is: $(get_config CLUSTER_REDIS_MASTER)"
    read -p "enter ip: " ip
    read -p "are you sure [Yn] " yesno
    if [ $yesno = "Y" ]; then
        set_config CLUSTER_REDIS_MASTER $ip
        info "redis master changed"
    fi

}
remove_redis_master() {
    echo "current master is: $(get_config CLUSTER_REDIS_MASTER)"
    read -p "are you sure [Yn] " yesno
    if [ $yesno = "Y" ]; then
        set_config CLUSTER_REDIS_MASTER ""
        info "redis master deleted"
    fi

}

show_es_peers() {
    local node_host=$(get_config CLUSTER_NODE_HOST)
    local node_ip=$(get_config CLUSTER_NODE_IP)

    local node_peers=$(get_config CLUSTER_ES_PEERS)
    echo ""
    echo "**** current peers *****"
    for line in $node_peers; do
        echo $line
    done

    echo ""

    echo "**** commands **********"
    echo "PEER=\"$node_host/$node_ip\""
    echo "ferrumgate --add-es-peer \$PEER"
}

add_es_peer() {
    if [ $# -lt 1 ]; then
        error "no arguments supplied"
        exit 1
    fi

    local input=$1
    local node_peers=$(get_config CLUSTER_ES_PEERS)
    local node_host=$(get_config CLUSTER_NODE_HOST)
    local node_ip=$(get_config CLUSTER_NODE_IP)
    local input_host=$(echo $input | cut -d'/' -f1)

    local peer=""
    for line in $node_peers; do
        local host=$(echo $line | cut -d'/' -f1)
        if [ $host != $input_host ]; then
            if [ -z "$peer" ]; then
                peer="$line"
            else
                peer="$peer $line"
            fi
        fi
    done

    if [ -z "$peer" ]; then
        peer="$input"
    else
        peer="$peer $input"
    fi

    set_config CLUSTER_ES_PEERS "$peer"
    info "added to peers"
}

remove_es_peer() {
    if [ $# -lt 1 ]; then
        error "no arguments supplied"
        exit 1
    fi

    local input=$1
    local node_peers=$(get_config CLUSTER_ES_PEERS)
    local node_host=$(get_config CLUSTER_NODE_HOST)
    local node_ip=$(get_config CLUSTER_NODE_IP)
    local input_host=$(echo $input | cut -d'/' -f1)

    local peer=""
    for line in $node_peers; do
        local host=$(echo $line | cut -d'/' -f1)
        if [ $host != $input_host ]; then
            if [ -z "$peer" ]; then
                peer="$line"
            else
                peer="$peer $line"
            fi
        fi
    done

    set_config CLUSTER_ES_PEERS "$peer"
    info "removed from peers"
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
    start-cluster,\
    stop-cluster,\
    status-cluster,\
    recreate-cluster-keys,\
    show-cluster-config,\
    add-cluster-peer:,\
    remove-cluster-peer:,\
    set-cluster-config,\
    set-redis-master,\
    remove-redis-master,\
    show-es-peers,\
    add-es-peer:,\
    remove-es-peer:,\
    show-config:,\
    set-config:,\
    all-logs' -- "$@") || exit
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
        --start-cluster)
            opt=16
            shift
            break
            ;;
        --stop-cluster)
            opt=17
            shift
            break
            ;;
        --status-cluster)
            opt=18
            shift
            break
            ;;
        --recreate-cluster-keys)
            opt=19
            shift
            break
            ;;
        --show-cluster-config)
            opt=20
            shift
            break
            ;;
        --add-cluster-peer)
            opt=21
            parameter_name="$2"
            shift 2
            break
            ;;
        --remove-cluster-peer)
            opt=22
            parameter_name="$2"
            shift 2
            break
            ;;
        --set-cluster-config)
            opt=23
            shift
            break
            ;;
        --set-redis-master)
            opt=24
            shift
            break
            ;;
        --remove-redis-master)
            opt=25
            shift
            break
            ;;
        --show-es-peers)
            opt=26
            shift
            break
            ;;
        --add-es-peer)
            opt=27
            parameter_name="$2"
            shift 2
            break
            ;;
        --remove-es-peer)
            opt=28
            parameter_name="$2"
            shift 2
            break
            ;;
        --show-config)
            opt=29
            parameter_name="$2"
            shift 2
            break
            ;;
        -c | --set-config)
            opt=30
            parameter_name="$2"
            shift 2
            break
            ;;
        --all-logs)
            opt=31
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
    [ $opt -eq 16 ] && start_cluster && exit 0
    [ $opt -eq 17 ] && stop_cluster && exit 0
    [ $opt -eq 18 ] && status_cluster && exit 0
    [ $opt -eq 19 ] && recreate_cluster_keys && exit 0
    [ $opt -eq 20 ] && show_cluster_config && exit 0
    [ $opt -eq 21 ] && add_cluster_peer $parameter_name && exit 0
    [ $opt -eq 22 ] && remove_cluster_peer $parameter_name && exit 0
    [ $opt -eq 23 ] && set_cluster_config && exit 0
    [ $opt -eq 24 ] && set_redis_master && exit 0
    [ $opt -eq 25 ] && remove_redis_master && exit 0
    [ $opt -eq 26 ] && show_es_peers && exit 0
    [ $opt -eq 27 ] && add_es_peer $parameter_name && exit 0
    [ $opt -eq 28 ] && remove_es_peer $parameter_name && exit 0
    [ $opt -eq 29 ] && show_config $parameter_name && exit 0
    [ $opt -eq 30 ] && config $parameter_name && exit 0
    [ $opt -eq 31 ] && all_logs $parameter_name && exit 0

}

main $*
