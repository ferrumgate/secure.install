#!/bin/sh
##################3 under development
#### include common.sh
if [ -f "common.sh" ]; then
    . ./common.sh
fi

if [ -f "./sh/common.sh" ]; then
    . ./sh/common.sh
fi

install() {
    info "installing microk8s"
    apt install --assume-yes snapd sudo
    snap install microk8s --classic --channel=1.24
    snap install yq
    export PATH=$PATH:/snap/bin
}

microk8s_install() {
    info "install microk8s if not installed"
    if [ $(command -v microk8s) ]; then
        info "microk8s is installed"
    else
        install
    fi

}

microk8s_check_isworking() {

    info "check microk8s is working"
    microk8s status | grep -q "is not running" && result=$? || result=$?
    [ $result -eq 0 ] && fatal "microk8s is not working, try microk8s start"
    info "microk8s is working"
}

microk8s_enable_modules() {
    info "microk8s enable dns, hostpath storage, ingress"
    microk8s enable dns hostpath-storage ingress
}

microk8s_enable_ipvs() {
    info "checking proxy mode is ipvs"
    local file=/var/snap/microk8s/current/args/kube-proxy
    local output=$(cat "$file" | grep "proxy-mode")
    if [ -z "$output" ]; then
        info "setting proxy mode ipvs"
        echo "--proxy-mode=ipvs" >>$file
        return $TRUE
    else
        info "proxy mode is ipvs"
        return $FALSE
    fi
}

microk8s_get_pod_cidr() {
    local file=/var/snap/microk8s/current/args/cni-network/cni.yaml
    local POD_CIDR=$(cat "$file" | grep -A1 -B0 "CALICO_IPV4POOL_CIDR" | grep value | cut -d":" -f2 | tr -d '"' | tr -d ' ')
    echo $POD_CIDR
}
microk8s_write_pod_cidr() {
    local cidr=$1
    [ -z $cidr ] && fatal "pod cidr needs an argument"

    local file=/var/snap/microk8s/current/args/kube-proxy
    local CLUSTER_CIDR=$(cat "$file" | grep cluster-cidr | cut -d'=' -f2)
    sed -i "s#$CLUSTER_CIDR#$cidr#g" $file

    file=/var/snap/microk8s/current/args/cni-network/cni.yaml
    local POD_CIDR=$(cat "$file" | grep -A1 -B0 "CALICO_IPV4POOL_CIDR" | grep value | cut -d":" -f2 | tr -d '"' | tr -d ' ')
    sed -i "s#$POD_CIDR#$cidr#g" $file

    microk8s kubectl apply -f $file

}

microk8s_get_service_cidr() {

    local file=/var/snap/microk8s/current/args/kube-apiserver
    local SERVICE_CIDR=$(cat "$file" | grep service-cluster-ip-range | cut -d'=' -f2)
    echo $SERVICE_CIDR
}

microk8s_write_service_cidr() {
    local cidr=$1
    [ -z $cidr ] && fatal "service cidr needs an argument"
    local file=/var/snap/microk8s/current/args/kube-apiserver
    local SERVICE_CIDR=$(cat "$file" | grep service-cluster-ip-range | cut -d'=' -f2)
    sed -i "s#$SERVICE_CIDR#$cidr#g" $file
}

microk8s_restart() {
    microk8s stop
    microk8s start
}
