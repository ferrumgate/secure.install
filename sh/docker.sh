#!/bin/bash
####
#### install docker on debian
####

#### include common.sh
if [ -f "common.sh" ]; then
    . ./common.sh
    . ./util.sh
fi

if [ -f "./sh/common.sh" ]; then
    . ./sh/common.sh
    . ./sh/util.sh
fi
docker_install() {
    info "installing docker"
    apt update --assume-yes
    apt remove docker docker.io containerd runc
    apt update --assume-yes
    apt upgrade --assume-yes

    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --batch --yes -o /etc/apt/keyrings/docker.gpg
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null

    apt update --assume-yes
    apt install --assume-yes --no-install-recommends docker-ce docker-ce-cli containerd.io docker-compose-plugin
    cat >/etc/docker/daemon.json <<EOF
{
        "default-address-pools" : [
    {
      "base" : "10.10.0.0/16",
      "size" : 24
    }
  ]
    }
EOF
    info "installed docker"
}

docker_bridge_create() {
    local name=$1
    local cidr=$2
    [ -z "$name" ] && fatal "docker_bridge_create needs argument"
    if [ -z "$cidr" ]; then
        info "used host ips are  $(host_networks)"
        info "used host routings are $(host_routings)"
        info "please select a non conflict docker network, from these ranges 10.0.0.0/16 ... 10.255.0.0/16 or 172.17.0.0/16 ... 172.31.0.0/16"
        info "you can select 10.10.10.0/24, if it does not conflict with your network or 172.31.30.0/24"
        cidr=$(read_cidr)
    fi
    local gateway=$(ipcalc -b $cidr | grep HostMin | cut -d ':' -f 2 | tr -d ' ')
    docker network create --driver bridge --subnet=$cidr \
        --gateway=$gateway --attachable $name
}

docker_network_bridge_configure() {
    local name=$1
    local cidr=$2
    [ -z "$name" ] && fatal "docker_network_bridge_configure needs argument"
    info "checking docker network $name"
    local network=$(docker network ls | grep $name)

    if [ -z "$network" ]; then
        info "$name network not exists"
        docker_bridge_create $name $cidr
    else

        info "$name network exists"
        local subnet=$(docker network inspect $name -f "{{range .IPAM.Config}}{{.Subnet}}{{end}}")
        info "selected $name subnet is $subnet"
        read -p "do you want to change [yN] " yesno
        if [ $yesno = "y" ]; then
            docker network rm $name
            docker_bridge_create $name
        fi
    fi

}
