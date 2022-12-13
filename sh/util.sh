#!/bin/bash

read_cidr() {

    while true; do

        read -p "enter cidr like (10.9.0.0/24):" network
        ipcalc -n "$network" | grep -q "INVALID" && result=$? || result=$?
        if [ $result -eq 0 ]; then
            error "invalid address"
        else
            echo $network
            break
        fi
    done

}

host_networks() {
    local tmp=$(ip a show scope global | grep inet | grep -v 127.0. | grep -v inet6 | tr -d 'inet' | grep /)
    local used_networks=$(echo $tmp | grep -E -o "(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?/[0-9]+)" | grep /)
    echo $used_networks
}

host_routings() {
    local tmp=$(ip route show | grep -v 127.0. | grep /)
    local used_networks=$(echo $tmp | grep -E -o "(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?/[0-9]+)" | grep /)
    echo $used_networks
}
