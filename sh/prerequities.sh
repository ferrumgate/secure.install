#!/bin/sh
#### include common.sh
if [ -f "common.sh" ]; then
    . ./common.sh
fi

if [ -f "./sh/common.sh" ]; then
    . ./sh/common.sh
fi

### install prerequities packages #####
prerequities() {

    ###
    info "update system"
    apt update --assume-yes
    apt upgrade --assume-yes

    ###
    #info "set locale to en_us UTF8"
    #locale
    #locale-gen en_US.UTF-8

    ###
    info "install some needed packages"
    apt install --assume-yes \
        curl \
        ipvsadm \
        ipset \
        sudo \
        unzip \
        tcpdump \
        dnsutils \
        bmon \
        htop \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        wireguard \
        ipcalc \
        net-tools \
        sysstat \
        xxd \
        conntrack \
        ntp \
        yq
    #install yq
    #YQ_VERSION=v4.2.0
    #YQ_BINARY=yq_linux_amd64
    #wget -q https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}.tar.gz -O - |
    #    tar xz && mv ${YQ_BINARY} /usr/bin/yq

    ####
    if [ -n "$FERRUM_LXD" ]; then
        info "load ipvs modules, and netfilter modules"
        cat <<EOF | tee /etc/modules-load.d/ferrumgate.conf
br_netfilter
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
ip_vs_lc
ip_vs_dh
ip_vs_sed
ip_vs_nq
nf_conntrack
EOF

        #### load modules to kernel
        modprobe -- br_netfilter
        modprobe -- ip_vs
        modprobe -- ip_vs_rr
        modprobe -- ip_vs_wrr
        modprobe -- ip_vs_sh
        modprobe -- ip_vs_lc
        modprobe -- ip_vs_dh
        modprobe -- ip_vs_sed
        modprobe -- ip_vs_nq
        modprobe -- nf_conntrack
        modprobe -- fuse

    fi
    LIMITS_FILE=/etc/security/limits.conf
    SOFT_LIMIT=$(cat $LIMITS_FILE | grep "root soft nofile 1048576" | grep -v "#" | wc -l)
    if [ $SOFT_LIMIT -eq "0" ]; then
        echo "root soft nofile 1048576" >>$LIMITS_FILE
    fi
    HARD_LIMIT=$(cat $LIMITS_FILE | grep "root hard nofile 1048576" | grep -v "#" | wc -l)
    if [ $HARD_LIMIT -eq "0" ]; then
        echo "root hard nofile 1048576" >>$LIMITS_FILE
    fi
    SOFT_LIMIT=$(cat $LIMITS_FILE | grep "* soft nofile 1048576" | grep -v "#" | wc -l)
    if [ $SOFT_LIMIT -eq "0" ]; then
        echo "* soft nofile 1048576" >>$LIMITS_FILE
    fi
    HARD_LIMIT=$(cat $LIMITS_FILE | grep "* hard nofile 1048576" | grep -v "#" | wc -l)
    if [ $HARD_LIMIT -eq "0" ]; then
        echo "* hard nofile 1048576" >>$LIMITS_FILE
    fi
    ulimit -Sn 1048576
    ulimit -Hn 1048576

    SYSCTL_FILE=/etc/sysctl.d/99-sysctl.conf
    if [ -n "$FERRUM_LXD" ]; then
        INOTIFY_USER_LIMIT=$(cat $SYSCTL_FILE | grep "fs.inotify.max_user_instances = 1024" | grep -v "#" | wc -l)
        if [ $INOTIFY_USER_LIMIT -eq "0" ]; then
            echo "fs.inotify.max_user_instances = 1024" >>$SYSCTL_FILE
        fi
    fi
    sysctl -p

}
