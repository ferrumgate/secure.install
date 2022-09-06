#!/bin/sh

### install prerequities packages #####

### update
apt update --assume-yes
apt upgrade --assume-yes

### locale 
locale
locale-gen en_US.UTF-8

### install some packages
apt install --assume-yes \
curl \
ipvsadm \
ipset \
sudo \
unzip \
tcpdump \
dnsutils \
iperf3 \
bmon \
htop \
ca-certificates \
curl \
gnupg \
lsb-release


#### load ipvs modules, and netfilter modules
cat <<EOF | sudo tee /etc/modules-load.d/ipvs.conf
br_netfilter
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
ip_vs_lc
ip_vs_dh
ip_vs_sed
ip_vs_nq
nf_conntrack_ipv4
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

