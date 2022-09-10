#!/bin/sh

#### include common.sh
if [ -f "common.sh" ]; then
    . ./common.sh
fi

if [ -f "./sh/common.sh" ]; then
    . ./sh/common.sh
fi

docker_swarm_install() {
    info "installing docker swarm"

    docker swarm init --cert-expiry 262800h0m0s
    docker network create --opt encrypted --driver overlay --subnet=10.100.0.0/16 \
        --gateway=10.100.0.1 \
        --attachable \
        ferrum

}
