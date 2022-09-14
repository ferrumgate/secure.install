microk8s_prepare_networks() {
    local is_changed=FALSE
    pods_cidr=$(microk8s_get_pod_cidr)
    cluster_cidr=$(microk8s_get_service_cidr)
    [ -z $pods_cidr ] || [ -z $cluster_cidr ] && fatal "getting k8s network cidr failed"
    info "###################################"
    info "pods network is: $pods_cidr"

    read -p "do you want to change it [yn]" input
    case $input in
    y)

        addr=$(read_cidr)
        microk8s_write_pod_cidr $addr
        is_changed=$TRUE
        ;;

    *) ;;

    esac

    info "###################################"
    info "cluster network is: $cluster_cidr"

    read -p "do you want to change it [yn]" input
    case $input in
    y)

        addr=$(read_cidr)
        microk8s_write_service_cidr $addr
        is_changed=$TRUE
        ;;

    *) ;;

    esac

    return $is_changed
}
