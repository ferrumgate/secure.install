# About

FerrumGate Zero Trust Access solution installation scripts for

- docker

### Usage

> sh install.sh --help

> sh install.sh --docker

> sh install.sh --version 1.8.0

### Installation

<https://ferrumgate.com/docs/getting-started/install/>

### Debugging

docker ps -q | xargs -L 1 -P `docker ps | wc -l` docker logs --since 30s -f
