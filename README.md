# secure.install

Zero trust application access system installation scripts for

- docker
- docker-swarm
- k8s

### Usage

> ./install.sh --help

> ./install.sh --docker

> ./install.sh --docker-swarm

#### Debugging

run a network tools container with below command in target container namespace

> docker run --rm -it --net container:$CID --privileged nicolaka/netshoot

### random number

cat /dev/urandom | tr -dc '[:alnum:]' | fold -w ${1:-32} | head -n 1
