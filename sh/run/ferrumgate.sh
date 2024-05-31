#!/bin/bash
# shellcheck disable=SC2022,SC2155

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
    if [ "$ENV_FOR" != "PROD" ]; then
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
    echo "  ferrumgate [ --version ]         -> prints version"
    echo "  ferrumgate [ --start ]        -> start service"
    echo "  ferrumgate [ --stop ]         -> stop service"
    echo "  ferrumgate [ --restart ]      -> restart service"
    echo "  ferrumgate [ --status ]       -> show status"
    echo "  ferrumgate [ --uninstall ]    -> uninstall"
    echo "  ferrumgate [ --set-config ] [redis,es,...] -> set config with name, redis"
    echo "  ferrumgate [ --show-config ] [var name] -> get config with name"
    echo "  ferrumgate [ --logs ] process -> get logs of process rest,log, parser, admin, task, quic"
    echo "  ferrumgate [ --list-gateways ]-> list gateways"
    echo "  ferrumgate [ --start-gateway ] gatewayId -> start a gateway"
    echo "  ferrumgate [ --stop-gateway ] gatewayId -> stop a gateway"
    echo "  ferrumgate [ --delete-gateway ] gatewayId  -> delete a gateway"
    echo "  ferrumgate [ --create-gateway ] -> creates a new gateway"
    echo "  ferrumgate [ --recreate-gateway ] -> recreates a gateway"
    echo "  ferrumgate [ --create-cluster ] -> create a cluster"
    echo "  ferrumgate [ --update-cluster ] -> update a cluster"
    echo "  ferrumgate [ --start-cluster ] -> starts cluster"
    echo "  ferrumgate [ --stop-cluster ] -> stop cluster"
    echo "  ferrumgate [ --restart-cluster ] -> restart cluster"
    echo "  ferrumgate [ --status-cluster ] -> cluster status"
    echo "  ferrumgate [ --recreate-cluster-keys ] -> recreate cluster keys"
    echo "  ferrumgate [ --show-cluster-config ] -> show cluster config"
    echo "  ferrumgate [ --add-cluster-peer ] peerVariable -> add a peer to cluster"
    echo "  ferrumgate [ --remove-cluster-peer ] peername -> remove peer from cluster"
    echo "  ferrumgate [ --set-cluster-config ] config -> change cluster config"
    echo "  ferrumgate [ --show-es-peers ] -> shows es peers"
    echo "  ferrumgate [ --add-es-peer ] peerVariable -> add a peer to es ha"
    echo "  ferrumgate [ --remove-es-peer ] peername -> remove a peer from es ha"
    echo "  ferrumgate [ --all-logs ] shows all logs"
    echo "  ferrumgate [ --upgrade-to-master ] make this host master"
    echo "  ferrumgate [ --upgrade-to-worker ] make this host worker"
    echo "  ferrumgate [ --show-config-all ] show all config"
    echo "  ferrumgate [ --cluster-add-worker ] add a worker to cluster"
    echo "  ferrumgate [ --cluster-join ] join to a cluster"
    echo "  ferrumgate [ --remove-worker ] remove a worker from cluster"
    echo "  ferrumgate [ --regenerate-cluster-keys ] regenerate cluster keys"

}

start_service() {

    start_base_and_gateways
    info "ferrumgate started"
    info "for more execute docker ps"
}

stop_service() {

    stop_base_and_gateways
    docker ps | grep "fg-" | tr -s ' ' | cut -d' ' -f 1 | xargs -r docker stop
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
    read -r -p "are you sure [Yn] " yesno
    if [ "$yesno" = "Y" ]; then

        info "uninstall started"
        systemctl stop ferrumgate
        systemctl disable ferrumgate
        ## force
        docker ps | grep "fg-" | tr -s ' ' | cut -d' ' -f 1 | xargs -r docker stop
        docker ps -a | grep "fg-" | tr -s ' ' | cut -d' ' -f 1 | xargs -r docker rm

        ## rm service
        rm /etc/systemd/system/ferrumgate.service
        ## rm folder
        rm -rf /etc/ferrumgate
        ## rm docker related
        docker network ls | grep "fg-" | tr -s ' ' | cut -d' ' -f2 | xargs -r docker network rm
        docker volume ls | grep "fg-" | tr -s ' ' | cut -d' ' -f2 | xargs -r docker volume rm
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
    result=$(echo "$1" | grep -E "gateway\.\w+\.yaml" || true)
    echo "$result"
}

find_default_gateway() {
    for file in "$ETC_DIR"/*; do
        file=$(basename "$file")
        local result=$(is_gateway_yaml "$file")
        if [ -n "$result" ]; then
            local gatewayId=$(echo "$file" | sed -e "s/gateway.//" -e "s/.yaml//")
            echo "$gatewayId"
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

    if [ "$service" = "rest" ]; then
        grepname=fg-base
        service="rest.portal"
    fi
    if [ "$service" = "redis" ]; then
        grepname=fg-base
    fi
    if [ "$service" = "es" ]; then
        grepname=fg-base
    fi
    if [ "$service" = "task" ]; then
        grepname=fg-base
        service="task"
    fi
    if [ $service = "log" ]; then
        grepname=fg-base
    fi
    if [ "$service" = "parser" ]; then
        grepname=fg-base
    fi

    if [ "$service" = "ssh" ]; then
        service="server.ssh"
    fi

    if [ "$service" = "quic" ]; then
        service="server.quic"
    fi

    if [ "$service" = "admin" ]; then
        service="job.admin"
    fi

    docker ps | grep "$grepname" | grep "$service" | cut -d" " -f1 | head -n1 | xargs -r docker logs -f
}

list_gateways() {

    for file in "$ETC_DIR"/*; do
        file=$(basename "$file")
        local result=$(is_gateway_yaml "$file")
        if [ -n "$result" ]; then

            local gatewayId=$(echo "$file" | sed -e "s/gateway.//" -e "s/.yaml//")

            info "$gatewayId"

        fi
    done
}
delete_gateway() {
    if [ $# -lt 1 ]; then
        error "no arguments supplied"
        exit 1
    fi
    local gateway_id="$1"
    stop_gateway "$gateway_id"
    rm -rf "$ETC_DIR/gateway.$gateway_id.yaml"
    docker network ls | grep "$gateway_id" | tr -s ' ' | cut -d' ' -f2 | xargs -r docker network rm
    docker volume ls | grep "$gateway_id" | tr -s ' ' | cut -d' ' -f2 | xargs -r docker volume rm

}

create_gateway() {
    local port=$1
    local gateway_id=$2
    if [ -z "$port" ]; then
        read -r -p "enter a port for ssh tunnel server: " p1
        port=$p1
    fi
    ## this must be lowercase , we are using with docker compose -p

    if [ -z "$gateway_id" ]; then
        gateway_id=$(cat /dev/urandom | tr -dc '[:alnum:]' | fold -w 16 | head -n 1 | tr '[:upper:]' '[:lower:]')
    fi
    DOCKER_FILE="$ETC_DIR/gateway.$gateway_id.yaml"
    rm -rf "$DOCKER_FILE"
    cp "$ETC_DIR/gateway.yaml" "$DOCKER_FILE"
    sed -i "s/??GATEWAY_ID/$gateway_id/g" "$DOCKER_FILE"
    sed -i "s/??SSH_PORT/$port/g" "$DOCKER_FILE"
    info "created gateway $gateway_id at port $port"
    info "start gateway"
}

recreate_gateway() {
    read -r -p "enter a port for ssh tunnel server: " port
    ## this must be lowercase , we are using with docker compose -p
    read -r -p "enter gateway id:" gateway_id
    create_gateway "$port" "$gateway_id"
}

is_master_host() {
    local role=$(get_config ROLES)
    local count=$(echo "$role" | grep "master" | wc -l)
    if [ ! "$count" -eq "0" ]; then
        echo "yes"
    else
        echo "no"
    fi
}

is_worker_host() {
    local role=$(get_config ROLES)
    local count=$(echo "$role" | grep "worker" | wc -l)
    if [ ! "$count" -eq "0" ]; then
        echo "yes"
    else
        echo "no"
    fi
}

get_docker_profile() {
    local profile=""
    if [ "$(is_master_host)" = "yes" ]; then
        profile="$profile --profile master"
    fi

    if [ "$(is_worker_host)" = "yes" ]; then
        profile="$profile --profile worker"
    fi
    echo "$profile"
}

start_base() {
    info "starting base"

    local FILE="$ETC_DIR/base.yaml"
    # just worker node
    if [ "$(is_worker_host)" = "yes" ] && [ "$(is_master_host)" = "no" ]; then
        info "this is a worker node"
        #sed -i "s|external:.*|external: false|g" $FILE
        yq -yi ".services.node.extra_hosts[0] |= \"registry.ferrumgate.zero:192.168.88.40\"" "$FILE"
        local peers=$(get_config CLUSTER_NODE_PEERSW)
        if [ -n "$peers" ]; then
            local tmp=$(echo "$peers" | cut -d'=' -f2-)
            local ip=$(echo "$tmp" | cut -d'/' -f3)
            yq -yi ".services.node.extra_hosts[1] |= \"redis-ha:$ip\"" "$FILE"
            yq -yi ".services.node.extra_hosts[2] |= \"redis:$ip\"" "$FILE"
            yq -yi ".services.node.extra_hosts[3] |= \"log:$ip\"" "$FILE"
        fi

        yq -yi "del(.services.node.depends_on)" "$FILE"

    else
        #sed -i "s|external:.*|external: true|g" $FILE
        yq -yi ".services.node.extra_hosts[0] |= \"registry.ferrumgate.zero:192.168.88.40\"" "$FILE"
        yq -yi ".services.node.depends_on[0] |= \"redis-ha\"" "$FILE"
    fi

    docker compose -f "$ETC_DIR/base.yaml" --env-file "$ETC_DIR/env" \
        $(get_docker_profile) -p fg-base up -d --remove-orphans
}
stop_base() {
    info "stoping base"
    docker compose -f "$ETC_DIR/base.yaml" --env-file "$ETC_DIR/env" \
        -p fg-base down
}

start_gateway() {
    if [ $# -lt 1 ]; then
        error "no arguments supplied"
        exit 1
    fi

    local gatewayId=$1
    info "starting gateway $gatewayId"
    local FILE="$ETC_DIR/gateway.$gatewayId.yaml"
    # just worker node
    if [ "$(is_worker_host)" = "yes" ] && [ "$(is_master_host)" = "no" ]; then
        info "this is a worker node"
        #sed -i "s|external:.*|external: false|g" $FILE
        yq -yi ".services.\"server-quic\".extra_hosts[0] |= \"registry.ferrumgate.zero:192.168.88.40\"" "$FILE"
        local peers=$(get_config CLUSTER_NODE_PEERSW)
        if [ -n "$peers" ]; then
            local tmp=$(echo "$peers" | cut -d'=' -f2-)
            local ip=$(echo "$tmp" | cut -d'/' -f3)
            yq -yi ".services.\"server-quic\".extra_hosts[1] |= \"redis-ha:$ip\"" "$FILE"
            yq -yi ".services.\"server-quic\".extra_hosts[2] |= \"redis:$ip\"" "$FILE"
            yq -yi ".services.\"server-quic\".extra_hosts[3] |= \"es-ha:$ip\"" "$FILE"
            yq -yi ".services.\"server-quic\".extra_hosts[4] |= \"es:$ip\"" "$FILE"
            yq -yi ".services.\"server-quic\".extra_hosts[5] |= \"log:$ip\"" "$FILE"
        fi

    else
        #sed -i "s|external:.*|external: true|g" $FILE
        yq -yi ".services.\"server-quic\".extra_hosts[0] |= \"registry.ferrumgate.zero:192.168.88.40\"" "$FILE"
    fi
    docker compose -f "$FILE" --env-file "$ETC_DIR/env" \
        $(get_docker_profile) -p "fg-$gatewayId" up -d --remove-orphans
}

prepare_env() {
    # prepare redis
    local redis_host=$(get_config REDIS_HOST)
    local redis_ha_host=$(get_config REDIS_HA_HOST)
    local is_redis_clustered=$(get_config CLUSTER_NODE_PEERS)
    if [ -z "$is_redis_clustered" ]; then
        info "redis is not clustered"
        set_config REDIS_PROXY_HOST "$redis_host"
        local redis_host_ssh=$(echo "$redis_host" | sed 's/:/#/g')
        set_config REDIS_HOST_SSH "$redis_host_ssh"
    else
        info "redis is clustered"
        set_config REDIS_PROXY_HOST "$redis_ha_host"
        local redis_host_ssh=$(echo "$redis_ha_host" | sed 's/:/#/g')
        set_config REDIS_HOST_SSH "$redis_host_ssh"

    fi

    # prepare redis intel
    local redis_intel_host=$(get_config REDIS_INTEL_HOST)
    local redis_intel_ha_host=$(get_config REDIS_INTEL_HA_HOST)
    local is_redis_intel_clustered=$(get_config CLUSTER_NODE_PEERS)
    if [ -z "$is_redis_intel_clustered" ]; then
        info "redis intel is not clustered"
        set_config REDIS_INTEL_PROXY_HOST "$redis_intel_host"
    else
        info "redis intel is clustered"
        set_config REDIS_INTEL_PROXY_HOST "$redis_intel_ha_host"
    fi

    local es_host=$(get_config ES_HOST)
    local es_ha_host=$(get_config ES_HA_HOST)
    local is_es_clustered=$(get_config CLUSTER_ES_PEERS)
    if [ -z "$is_es_clustered" ]; then
        set_config ES_PROXY_HOST "$es_host"
    else
        set_config ES_PROXY_HOST "$es_ha_host"
    fi

    if [ "$(is_master_host)" = "no" ] && [ "$(is_worker_host)" = "yes" ]; then
        #if this is a worker host
        set_config ES_PROXY_HOST "$es_host"
        set_config REDIS_PROXY_HOST "$redis_host"
        local redis_host_ssh=$(echo "$redis_host" | sed 's/:/#/g')
        set_config REDIS_HOST_SSH "$redis_host_ssh"

    fi
}

start_base_and_gateways() {
    prepare_env

    if [ "$(is_cluster_working)" = "no" ]; then
        start_cluster
    fi

    start_base

    for file in "$ETC_DIR"/*; do
        file=$(basename "$file")
        local result=$(is_gateway_yaml "$file")
        if [ -n "$result" ]; then
            local gatewayId=$(echo "$file" | sed -e "s/gateway.//" -e "s/.yaml//")
            start_gateway "$gatewayId"
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
    docker compose -f "$ETC_DIR/gateway.$gatewayId.yaml" --env-file "$ETC_DIR/env" \
        -p "fg-$gatewayId" down
}

stop_base_and_gateways() {

    for file in "$ETC_DIR"/*; do
        file=$(basename "$file")
        local result=$(is_gateway_yaml "$file")
        if [ -n "$result" ]; then

            local gatewayId=$(echo "$file" | sed -e "s/gateway.//" -e "s/.yaml//")
            stop_gateway "$gatewayId"
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
    value=$(cat "$file" | grep "$key=" | cut -d"=" -f2-)
    echo "$value"
}

get_config_from() {
    if [ $# -lt 2 ]; then
        error "no arguments supplied"
        exit 1
    fi

    local key=$1
    value=$(echo "$2" | grep "$key=" | cut -d"=" -f2-)
    echo "$value"
}

show_config() {
    get_config "$1"
}

change_config() {
    if [ $# -lt 1 ]; then
        error "no arguments supplied"
        exit 1
    fi

    local param=$1
    local key=$(echo "$param" | cut -d'=' -f1)
    local value=$(echo "$param" | cut -d'=' -f2-)

    if [ "$key" = "ES_HOST" ]; then

        set_config ES_HOST "$value"
        set_config ES_INTEL_HOST "$value"
    fi
    if [ "$key" = "ES_PASS" ]; then

        set_config ES_PASS "$value"
        set_config ES_INTEL_PASS "$value"
    fi

    set_config "$key" "$value"

}
all_logs() {
    docker ps -q | xargs -L 1 -P $(docker ps | wc -l) docker logs --since 30s -f
}

create_cluster_ip() {
    local random=$(shuf -i 1-254 -n1)
    echo "169.254.254.$random"
}
show_version() {
    echo "$VERSION"
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
    if [ "$count" -eq "0" ]; then
        echo "no"
    else
        echo "yes"
    fi
}

stop_cluster() {

    if [ "$(is_cluster_working)" = "no" ]; then
        info "cluster is not working"
        return
    fi
    info "stoping wgferrum"
    wg-quick down wgferrum 2>/dev/null || true
    ip link del dev wgferrum 2>/dev/null || true

    info "stoping wgferrumw"
    wg-quick down wgferrumw 2>/dev/null || true
    ip link del dev wgferrumw 2>/dev/null || true

    info "stopped cluster"
    stop_firewall
    info "firewall rules cleared"
}
stop_firewall() {
    firewall_rules_count=$(iptables -S INPUT | grep wgferrum | wc -l)
    for _i in $(seq 1 "$firewall_rules_count"); do
        iptables -D INPUT -i wgferrum+ ! -d 169.254.0.0/16 -j DROP || true
    done

}
start_firewall() {
    stop_firewall
    firewall_rules_count=$(iptables -S INPUT | grep wgferrum | wc -l)
    if [ "$firewall_rules_count" -eq "0" ]; then
        iptables -A INPUT -i wgferrum+ ! -d 169.254.0.0/16 -j DROP
    fi
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

    FILE=/etc/wireguard/wgferrum.conf
    echo "[Interface]" >$FILE
    echo "Address=$node_ip/32" >>$FILE
    echo "ListenPort=$node_port" >>$FILE
    echo "PrivateKey=$(echo "$node_private_key" | xxd -r -p | base64)" >>$FILE
    for line in $node_peers; do
        echo "[Peer]" >>$FILE
        echo "Endpoint=$(echo "$line" | cut -d'/' -f2)" >>$FILE
        echo "AllowedIPs=$(echo "$line" | cut -d'/' -f3)" >>$FILE
        echo "PublicKey=$(echo "$line" | cut -d'/' -f4 | xxd -r -p | base64)" >>$FILE
    done

    # start worker interfaces
    local node_ip=$(get_config CLUSTER_NODE_IPW)
    local node_port=$(get_config CLUSTER_NODE_PORTW)

    FILE=/etc/wireguard/wgferrumw.conf
    echo "[Interface]" >"$FILE"
    echo "Address=$node_ip/32" >>"$FILE"
    echo "ListenPort=$node_port" >>"$FILE"
    echo "PrivateKey=$(echo "$node_private_key" | xxd -r -p | base64)" >>"$FILE"
    local node_peersw=$(get_config CLUSTER_NODE_PEERSW)
    for line in $node_peersw; do
        echo "[Peer]" >>"$FILE"
        echo "Endpoint=$(echo "$line" | cut -d'/' -f2)" >>"$FILE"
        echo "AllowedIPs=$(echo "$line" | cut -d'/' -f3)" >>"$FILE"
        echo "PublicKey=$(echo "$line" | cut -d'/' -f4 | xxd -r -p | base64)" >>"$FILE"
        echo ""
    done

    info "starting wgferrum"
    wg-quick up wgferrum

    info "starting wgferrumw"
    wg-quick up wgferrumw

    info "started cluster"
    start_firewall
    info "firewal rules applied"
}

status_cluster() {
    wg show
}
create_cluster_private_key() {
    wg genkey | base64 -d | xxd -p -c 256
}
create_cluster_public_key() {
    echo "$1" | xxd -r -p | base64 | wg pubkey | base64 -d | xxd -p -c 256
}
recreate_cluster_keys() {
    local pri=$(create_cluster_private_key)
    local pub=$(create_cluster_public_key "$pri")
    set_config CLUSTER_NODE_PRIVATE_KEY "$pri"
    set_config CLUSTER_NODE_PUBLIC_KEY "$pub"
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

    local cluster_public_ip=$(get_config CLUSTER_NODE_PUBLIC_IP)
    if [ -z "$cluster_public_ip" ] && [ "$(is_master_host)" = "yes" ]; then
        echo "please set host public ip and port that other master hosts can reach master, with below commands"
        echo "ferrumgate --set-config CLUSTER_NODE_PUBLIC_IP=\$IP"
        echo "ferrumgate --set-config CLUSTER_NODE_PUBLIC_PORT=\$PORT"
        return
    fi

    local cluster_public_port=$(get_config CLUSTER_NODE_PUBLIC_PORT)
    if [ -z "$cluster_public_port" ] && [ "$(is_master_host)" = "yes" ]; then
        echo "please set host public ip that other master hosts can reach to this master, with below commands"
        echo "ferrumgate --set-config CLUSTER_NODE_PUBLIC_IP=\$IP"
        echo "ferrumgate --set-config CLUSTER_NODE_PUBLIC_PORT=\$PORT"
        return
    fi

    local cluster_public_ipw=$(get_config CLUSTER_NODE_PUBLIC_IPW)
    if [ -z "$cluster_public_ipw" ]; then
        echo "please set host public ip and port that worker hosts can reach to master, with below commands"
        echo "ferrumgate --set-config CLUSTER_NODE_PUBLIC_IPW=\$IP"
        echo "ferrumgate --set-config CLUSTER_NODE_PUBLIC_PORTW=\$PORT"
        return
    fi

    local cluster_public_portw=$(get_config CLUSTER_NODE_PUBLIC_PORTW)
    if [ -z "$cluster_public_portw" ]; then
        echo "please set host public ip that worker hosts can reach to master, with below commands"
        echo "ferrumgate --set-config CLUSTER_NODE_PUBLIC_IPW=\$IP"
        echo "ferrumgate --set-config CLUSTER_NODE_PUBLIC_PORTW=\$PORT"
        return
    fi

    local node_host=$(get_config CLUSTER_NODE_HOST)
    local node_ip=$(get_config CLUSTER_NODE_IP)
    local node_port=$(get_config CLUSTER_NODE_PORT)
    local node_ipw=$(get_config CLUSTER_NODE_IPW)
    local node_portw=$(get_config CLUSTER_NODE_PORTW)
    local node_public_key=$(get_config CLUSTER_NODE_PUBLIC_KEY)

    local node_peers=$(get_config CLUSTER_NODE_PEERS)
    echo ""
    echo "**** current peers *****"
    for line in $node_peers; do
        echo "$line"
    done

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
    echo "wg set wgferrum peer $(echo "$node_public_key" | xxd -r -p | base64) allowed-ips $node_ip"
    echo "******************************************************************************"
    if [ "$(is_master_host)" = "yes" ]; then
        echo "PEER=$node_host/$cluster_public_ip:$cluster_public_port/$node_ip/$node_public_key"
        echo "PEERW=$node_host/$cluster_public_ipw:$cluster_public_portw/$node_ipw/$node_public_key"
    else
        echo "PEERW=$node_host/$cluster_public_ipw:$cluster_public_portw/$node_ipw/$node_public_key"
    fi

}

get_cluster_config_public_peer() {
    local node_host=$(get_config CLUSTER_NODE_HOST)
    local node_ip=$(get_config CLUSTER_NODE_IP)
    local node_port=$(get_config CLUSTER_NODE_PORT)
    local node_ipw=$(get_config CLUSTER_NODE_IPW)
    local node_portw=$(get_config CLUSTER_NODE_PORTW)
    local cluster_public_ip=$(curl --silent ifconfig.me/ip)
    set_config CLUSTER_NODE_PUBLIC_IP "$cluster_public_ip"
    set_config CLUSTER_NODE_PUBLIC_IPW "$cluster_public_ip"
    local cluster_public_port=$(get_config CLUSTER_NODE_PUBLIC_PORT)
    if [ -z "$cluster_public_port" ]; then
        cluster_public_port=54310
        set_config CLUSTER_NODE_PUBLIC_PORT 54310
    fi
    local cluster_public_portw=$(get_config CLUSTER_NODE_PUBLIC_PORTW)
    if [ -z "$cluster_public_portw" ]; then
        cluster_public_portw=54309
        set_config CLUSTER_NODE_PUBLIC_PORTW 54309
    fi
    local node_public_key=$(get_config CLUSTER_NODE_PUBLIC_KEY)
    if [ "$(is_master_host)" = "yes" ]; then
        echo "PEER=$node_host/$cluster_public_ip:$cluster_public_port/$node_ip/$node_public_key"
        echo "PEERW=$node_host/$cluster_public_ip:$cluster_public_portw/$node_ipw/$node_public_key"
    else
        echo "PEERW=$node_host/$cluster_public_ip:$cluster_public_portw/$node_ipw/$node_public_key"
    fi
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
    local input_host=$(echo "$input" | cut -d'/' -f1)

    if [ "$input_host" = "$node_host" ]; then
        error "you can not add this host to cluster peers"
        return
    fi

    local peer=""
    for line in $node_peers; do
        local host=$(echo "$line" | cut -d'/' -f1)
        if [ "$host" != "$input_host" ]; then
            peer="$peer $line"
        fi
    done
    peer="$peer $input"
    # shellcheck disable=SC2086
    peer=$(echo $peer) #trim

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
    local input_host=$(echo "$input" | cut -d'/' -f1)

    local peer=""
    for line in $node_peers; do
        local host=$(echo "$line" | cut -d'/' -f1)
        if [ "$host" != "$input_host" ]; then
            peer="$peer $line"
        fi
    done

    set_config CLUSTER_NODE_PEERS "$peer"
    info "removed from peers"
}

set_cluster_config() {
    show_cluster_info
    echo "which option do you want to change?"
    read -r -p "type host, ip, port, key: " selection

    if [ "$selection" = "host" ]; then
        read -r -p "enter hostname: " hostname
        read -r -p "are you sure [Yn] " yesno
        if [ "$yesno" = "Y" ]; then
            set_config CLUSTER_NODE_HOST "$hostname"
            info "cluster host changed"
        fi
    fi
    if [ "$selection" = "ip" ]; then
        read -r -p "enter ip: " ip
        read -r -p "are you sure [Yn] " yesno
        if [ "$yesno" = "Y" ]; then
            set_config CLUSTER_NODE_IP "$ip"
            info "cluster ip changed"
        fi
    fi

    if [ "$selection" = "port" ]; then
        read -r -p "enter port: " port
        read -r -p "are you sure [Yn] " yesno
        if [ "$yesno" = "Y" ]; then
            set_config CLUSTER_NODE_PORT "$port"
            info "cluster port changed"
        fi
    fi

    if [ "$selection" = "key" ]; then
        read -r -p "are you sure [Yn] " yesno
        if [ "$yesno" = "Y" ]; then
            recreate_cluster_keys
            info "cluster keys changed"
        fi
    fi

}

add_es_peer() {
    if [ $# -lt 1 ]; then
        error "no arguments supplied"
        exit 1
    fi

    local input=$1
    local es_peers=$(get_config CLUSTER_ES_PEERS)
    local node_host=$(get_config CLUSTER_NODE_HOST)
    local node_ip=$(get_config CLUSTER_NODE_IP)
    local input_host=$(echo "$input" | cut -d'/' -f1)
    local input_ip=$(echo "$input" | cut -d'/' -f3)

    local peer=""
    for line in $es_peers; do
        local host=$(echo "$line" | cut -d'/' -f1)
        if [ "$host" != "$input_host" ]; then
            peer="$peer $line"
        fi
    done
    peer="$peer $input_host/$input_ip"
    # shellcheck disable=SC2086
    peer=$(echo $peer) #trim

    set_config CLUSTER_ES_PEERS "$peer"
    info "added to es peers"
}

remove_es_peer() {
    if [ $# -lt 1 ]; then
        error "no arguments supplied"
        exit 1
    fi

    local input=$1
    local es_peers=$(get_config CLUSTER_ES_PEERS)
    local node_host=$(get_config CLUSTER_NODE_HOST)
    local node_ip=$(get_config CLUSTER_NODE_IP)
    local input_host=$(echo "$input" | cut -d'/' -f1)

    local peer=""
    for line in $es_peers; do
        local host=$(echo "$line" | cut -d'/' -f1)
        if [ "$host" != "$input_host" ]; then
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

upgrade_to_master() {
    info "changing host role to master"
    set_config ROLES "master"
}
upgrade_to_worker() {
    info "changing host role to worker"
    set_config ROLES "worker"
}

show_config_all() {
    cat /etc/ferrumgate/env
    echo "**********************************************"
    # shellcheck disable=SC2022
    echo "ferrumgate --set-config-all $(cat /etc/ferrumgate/env | base64 -w 0)"
}
##
## if you change this funnction
## remember also change nodes.component.ts in
## ui.portal project
##
set_config_all() {
    if [ $# -lt 1 ]; then
        error "no arguments supplied"
        exit 1
    fi

    local input=$(echo "$1" | base64 -d)

    local redis_pass=$(get_config_from REDIS_PASS "$input")
    set_config REDIS_PASS "$redis_pass"

    local redis_intel_pass=$(get_config_from REDIS_INTEL_PASS "$input")
    set_config REDIS_INTEL_PASS "$redis_intel_pass"

    local encrypt_key=$(get_config_from ENCRYPT_KEY "$input")
    set_config ENCRYPT_KEY "$encrypt_key"

    local es_pass=$(get_config_from ES_PASS "$input")
    set_config ES_PASS "$es_pass"

    local es_intel_pass=$(get_config_from ES_INTEL_PASS "$input")
    set_config ES_INTEL_PASS "$es_intel_pass"

    local ferrum_cloud_id=$(get_config_from FERRUM_CLOUD_ID "$input")
    set_config FERRUM_CLOUD_ID "$ferrum_cloud_id"

    local ferrum_cloud_url=$(get_config_from FERRUM_CLOUD_URL "$input")
    set_config FERRUM_CLOUD_URL "$ferrum_cloud_url"

    local ferrum_cloud_token=$(get_config_from FERRUM_CLOUD_TOKEN "$input")
    set_config FERRUM_CLOUD_TOKEN "$ferrum_cloud_token"

    if [ "$(is_master_host)" = "yes" ]; then

        local node_ipw=$(get_config_from CLUSTER_NODE_IPW "$input")
        set_config CLUSTER_NODE_IPW "$node_ipw"

        local node_portw=$(get_config_from CLUSTER_NODE_PORTW "$input")
        set_config CLUSTER_NODE_PORTW "$node_portw"

        local node_privatekey=$(get_config_from CLUSTER_NODE_PRIVATE_KEY "$input")
        set_config CLUSTER_NODE_PRIVATE_KEY "$node_privatekey"

        local node_publickey=$(get_config_from CLUSTER_NODE_PUBLIC_KEY "$input")
        set_config CLUSTER_NODE_PUBLIC_KEY "$node_publickey"
    fi

}

is_redis_master_role() {
    local redis_host="$1"
    local redis_port="$2"
    local redis_pass="$3"
    local result=$(docker run redis:7-bullseye redis-cli --no-auth-warning -h "$redis_host" -p "$redis_port" --pass "$redis_pass" role)
    result=$(echo "$result" | grep "master" | wc -l)
    if [ "$result" != 0 ]; then
        echo "yes"
    else
        echo "no"
    fi
}

create_redis_cluster() {
    if [ $# -lt 1 ]; then
        error "no arguments supplied"
        exit 1
    fi
    info "creating redis cluster"

    local redis_pass=$(get_config REDIS_PASS)
    local redis_intel_pass=$(get_config REDIS_INTEL_PASS)
    local node_host=$(get_config CLUSTER_NODE_HOST)
    local node_ip=$(get_config CLUSTER_NODE_IP)
    counter=0
    local peers="$1"
    local redis_master_host=
    local redis_master_ip=
    local redis_intel_master_host=
    local redis_intel_master_ip=

    # find master host and ip
    for line in $(echo "$peers" | tr " " "\n"); do
        counter=$((counter + 1))
        local peer=$(echo "$line" | cut -d'=' -f1)
        if [ "$peer" = "PEER" ]; then

            local data=$(echo "$line" | cut -d'=' -f2)
            peer_host=$(echo "$data" | cut -d'/' -f1)
            peer_ip=$(echo "$data" | cut -d'/' -f3)
            info "checking is redis master $peer_ip:6379"
            local is_master=$(is_redis_master_role "$peer_ip" 6379 "$redis_pass")
            if [[ "$is_master" = "yes" ]] && [[ -z $redis_master_host ]]; then
                redis_master_host=$peer_host
                redis_master_ip=$peer_ip
                set_config CLUSTER_REDIS_MASTER "$peer_ip"
                info "redis master found $peer_ip:6379"
            fi

            info "checking is redis master $peer_ip:6380"
            local is_master=$(is_redis_master_role "$peer_ip" 6380 "$redis_pass")
            if [[ "$is_master" = "yes" ]] && [[ -z $redis_intel_master_host ]]; then
                redis_intel_master_host=$peer_host
                redis_intel_master_ip=$peer_ip
                set_config CLUSTER_REDIS_INTEL_MASTER "$peer_ip"
                info "redis intel master found $peer_ip:6380"
            fi

        fi

    done

    if [ -z "$redis_master_host" ]; then
        error "redis master not found"
        return
    fi

    if [ -z "$redis_intel_master_host" ]; then
        error "redis intel master not found"
        return
    fi

    if [ "$node_ip" != "$redis_master_ip" ]; then # this is not master machine
        info "creating redis cluster"
        ## prepare redis
        local port=6379
        docker run redis:7-bullseye redis-cli --no-auth-warning -h "$node_ip" -p "$port" --pass "$redis_pass" replicaof "$redis_master_ip" "$port"
        docker run redis:7-bullseye redis-cli --no-auth-warning -h "$node_ip" -p "$port" --pass "$redis_pass" config rewrite

    fi
    if [ "$node_ip" != "$redis_intel_master_ip" ]; then # this is not master machine
        info "creating redis intel cluster"
        ## prepare intel redis
        local port=6380
        docker run redis:7-bullseye redis-cli --no-auth-warning -h "$node_ip" -p "$port" --pass "$redis_pass" replicaof "$redis_intel_master_ip" "$port"
        docker run redis:7-bullseye redis-cli --no-auth-warning -h "$node_ip" -p "$port" --pass "$redis_pass" config rewrite
    fi

}

create_cluster() {
    read -r -p "do you want to continue [Yn] " yesno
    if [ "$yesno" = "Y" ]; then
        echo "paste peers and ctrl-d when done:"
        local peers=$(cat)
        set_config CLUSTER_NODE_PEERS ""
        set_config CLUSTER_ES_PEERS ""

        for line in $(echo "$peers" | tr " " "\n"); do
            local peer=$(echo "$line" | cut -d'=' -f1)
            if [ "$peer" = "PEER" ]; then
                local tmp=$(echo "$line" | cut -d'=' -f2-)
                info "adding $tmp"
                add_cluster_peer "$tmp"
                add_es_peer "$tmp"
            fi
        done
        start_cluster

        create_redis_cluster "$peers"
    fi

}
update_cluster() {
    create_cluster
}

cluster_add_worker() {
    if [ "$(is_master_host)" = "no" ]; then
        error "only master can add worker"
        info "ferrumgate --upgrade-to-master"
        return
    fi

    read -r -p "do you want to continue [Yn] " yesno
    if [ "$yesno" = "Y" ]; then
        echo "paste peers and ctrl-d when done:"
        local saved_peers=$(get_config CLUSTER_NODE_PEERSW)
        local peers=$(cat)
        set_config CLUSTER_NODE_PEERSW ""
        for line in $(echo "$peers" | tr " " "\n"); do
            local peer=$(echo "$line" | cut -d'=' -f1)
            if [ "$peer" = "PEERW" ]; then
                local tmp=$(echo "$line" | cut -d'=' -f2-)
                info "adding $tmp"
                if [ -z "$saved_peers" ]; then
                    saved_peers="$tmp"
                else
                    saved_peers="$saved_peers $tmp"
                fi
            fi
        done
        set_config CLUSTER_NODE_PEERSW "$saved_peers"
        start_cluster
    fi
}

cluster_remove_worker() {
    if [ "$(is_master_host)" = "no" ]; then
        error "only master can add worker"
        info "ferrumgate --upgrade-to-master"
        return
    fi

    read -r -p "do you want to continue [Yn] " yesno
    if [ "$yesno" = "Y" ]; then
        echo "paste hostname, or ip and ctrl-d when done:"
        local saved_peers=$(get_config CLUSTER_NODE_PEERSW)
        local input=$(cat)
        local output=""
        set_config CLUSTER_NODE_PEERSW ""
        for line in $(echo "$saved_peers" | tr " " "\n"); do

            local host=$(echo "$line" | cut -d'/' -f1)
            local ip_public=$(echo "$line" | cut -d'/' -f2 | cut -d':' -f1)
            local ipw=$(echo "$line" | cut -d'/' -f3)

            if [ "$input" != "$host" ] && [ "$input" != "$ip_public" ] && [ "$input" != "$ipw" ]; then
                if [ -z "$output" ]; then
                    output="$line"
                else
                    output="$output $line"
                fi
            fi

        done
        set_config CLUSTER_NODE_PEERSW "$output"
        start_cluster
    fi

}

cluster_join() {

    if [ "$(is_worker_host)" = "yes" ] && [ "$(is_master_host)" = "no" ]; then
        echo -n ""
    else
        error "only worker can join"
        info "ferrumgate --upgrade-to-worker"
        return
    fi
    local peers=""
    if [[ $# -lt 1 ]] || [[ -z $1 ]]; then
        read -r -p "do you want to continue [Yn] " yesno
        if [ "$yesno" != "Y" ]; then
            return
        fi
        echo "paste peer and ctrl-d when done:"
        peers=$(cat)
    else
        peers=$1
    fi

    set_config CLUSTER_NODE_PEERSW ""
    for line in $(echo "$peers" | tr " " "\n"); do
        local peer=$(echo "$line" | cut -d'=' -f1)
        if [ "$peer" = "PEERW" ]; then
            local tmp=$(echo "$line" | cut -d'=' -f2-)
            set_config CLUSTER_NODE_PEERSW "$tmp"
            break
        fi
    done
    start_cluster

}

create_cluster_private_key() {
    wg genkey | base64 -d | xxd -p -c 256
}
create_cluster_public_key() {
    echo "$1" | xxd -r -p | base64 | wg pubkey | base64 -d | xxd -p -c 256
}

regenerate_cluster_keys() {
    local pri=$(create_cluster_private_key)
    local pub=$(create_cluster_public_key "$pri")
    set_config CLUSTER_NODE_PRIVATE_KEY "$pri"
    set_config CLUSTER_NODE_PUBLIC_KEY "$pub"
    info "regenerated keys"
}

create_cluster_ip() {
    local random=$(shuf -i 20-254 -n1)
    echo "169.254.254.$random"
}

regenerate_cluster_ips() {
    local ip=$(create_cluster_ip)
    set_config CLUSTER_NODE_IP "$ip"
    local ipw=$(create_cluster_ip)
    set_config CLUSTER_NODE_IPW "$ipw"
    info "regenerated ips"
}

main() {
    ensure_root

    ARGS=$(getopt -o 'hsxrtul:c:g:' --long '\
    help,start,stop,restart,status,uninstall,\
    logs:,\
    gateway:,\
    start-base-and-gateways,\
    stop-base-and-gateways,\
    list-gateways,\
    start-gateway:,\
    stop-gateway:,\
    delete-gateway:,\
    create-gateway,\
    recreate-gateway,\
    start-cluster,\
    stop-cluster,\
    restart-cluster,\
    status-cluster,\
    recreate-cluster-keys,\
    show-cluster-config,\
    add-cluster-peer:,\
    remove-cluster-peer:,\
    set-cluster-config,\
    set-redis-master,\
    remove-redis-master,\
    add-es-peer:,\
    remove-es-peer:,\
    show-config:,\
    set-config:,\
    version,\
    upgrade-to-master,\
    upgrade-to-worker,\
    show-config-all,\
    set-config-all:,\
    create-cluster,\
    update-cluster,\
    cluster-add-worker,\
    cluster-remove-worker,\
    cluster-join::,\
    regenerate-cluster-keys,\
    get-cluster-config-public-peer,\
    all-logs' -- "$@") || exit
    eval set -- "$ARGS"
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
        --start-base-and-gateways)
            opt=8
            shift
            break
            ;;
        --stop-base-and-gateways)
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
        --version)
            opt=31
            shift
            break
            ;;
        --all-logs)
            opt=32
            shift
            break
            ;;
        --upgrade-to-master)
            opt=33
            shift
            break
            ;;
        --upgrade-to-worker)
            opt=34
            shift
            break
            ;;
        --show-config-all)
            opt=35
            shift
            break
            ;;
        --set-config-all)
            opt=36
            parameter_name="$2"
            shift 2
            break
            ;;
        --create-cluster)
            opt=37
            shift
            break
            ;;
        --cluster-add-worker)
            opt=38
            shift
            break
            ;;
        --cluster-join)
            opt=39
            shift
            # shellcheck disable=SC2236
            if [ -n "$3" ]; then
                parameter_name="$3"
                shift
            fi
            break
            ;;
        --restart-cluster)
            opt=40
            shift
            break
            ;;
        --regenerate-cluster-keys)
            opt=41
            shift
            break
            ;;
        --regenerate-cluster-ips)
            opt=42
            shift
            break
            ;;
        --get-cluster-config-public-peer)
            opt=43
            shift
            break
            ;;
        --update-cluster)
            opt=44
            shift
            break
            ;;
        --cluster-remove-worker)
            opt=45
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

    if [ -z "$gateway_id" ]; then
        gateway_id=$(find_default_gateway)
    fi

    [ $opt -eq 1 ] && print_usage && exit 0
    [ $opt -eq 2 ] && start_service && exit 0
    [ $opt -eq 3 ] && stop_service && exit 0
    [ $opt -eq 4 ] && restart_service && exit 0
    [ $opt -eq 5 ] && status_service && exit 0
    [ $opt -eq 6 ] && logs "$gateway_id" "$service_name" && exit 0
    [ $opt -eq 7 ] && uninstall && exit 0
    [ $opt -eq 8 ] && start_base_and_gateways && exit 0
    [ $opt -eq 9 ] && stop_base_and_gateways && exit 0
    [ $opt -eq 10 ] && list_gateways && exit 0
    [ $opt -eq 11 ] && start_gateway "$gateway_id" && exit 0
    [ $opt -eq 12 ] && stop_gateway "$gateway_id" && exit 0
    [ $opt -eq 13 ] && delete_gateway "$gateway_id" && exit 0
    [ $opt -eq 14 ] && create_gateway && exit 0
    [ $opt -eq 15 ] && recreate_gateway && exit 0
    [ $opt -eq 16 ] && start_cluster && exit 0
    [ $opt -eq 17 ] && stop_cluster && exit 0
    [ $opt -eq 18 ] && status_cluster && exit 0
    [ $opt -eq 19 ] && recreate_cluster_keys && exit 0
    [ $opt -eq 20 ] && show_cluster_config && exit 0
    [ $opt -eq 21 ] && add_cluster_peer "$parameter_name" && exit 0
    [ $opt -eq 22 ] && remove_cluster_peer "$parameter_name" && exit 0
    [ $opt -eq 23 ] && set_cluster_config && exit 0
    [ $opt -eq 26 ] && show_es_peers && exit 0
    [ $opt -eq 27 ] && add_es_peer "$parameter_name" && exit 0
    [ $opt -eq 28 ] && remove_es_peer "$parameter_name" && exit 0
    [ $opt -eq 29 ] && show_config "$parameter_name" && exit 0
    [ $opt -eq 30 ] && change_config "$parameter_name" && exit 0
    [ $opt -eq 31 ] && show_version && exit 0
    [ $opt -eq 32 ] && all_logs "$parameter_name" && exit 0
    [ $opt -eq 33 ] && upgrade_to_master && exit 0
    [ $opt -eq 34 ] && upgrade_to_worker && exit 0
    [ $opt -eq 35 ] && show_config_all && exit 0
    [ $opt -eq 36 ] && set_config_all "$parameter_name" && exit 0
    [ $opt -eq 37 ] && create_cluster && exit 0
    [ $opt -eq 38 ] && cluster_add_worker && exit 0
    [ $opt -eq 39 ] && cluster_join "$parameter_name" && exit 0
    [ $opt -eq 40 ] && start_cluster && exit 0
    [ $opt -eq 41 ] && regenerate_cluster_keys && exit 0
    [ $opt -eq 42 ] && regenerate_cluster_ips && exit 0
    [ $opt -eq 43 ] && get_cluster_config_public_peer && exit 0
    [ $opt -eq 44 ] && update_cluster && exit 0
    [ $opt -eq 45 ] && cluster_remove_worker && exit 0

}

main "$@"
