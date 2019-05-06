# app-controller
show/start/stop the apps of a server

## Prerequisition

``` Shell

# Ubuntu
sudo apt-get install cpanminus -y

# CentOS
sudo yum install cpanminus -y

# install YAML
cpanm YAML
```

## Installation

``` Shell
# download
git clone git@github.com:zhanglintc/app-controller.git
cd app-controller

# install
./install.pl

# uninstall
./uninstall.pl
```

`install.pl` would try to make a soft link:
`ln -s /path-to-app-contoller/app-controller.pl /usr/local/bin/apc`.

`install.pl` would also make a folder:
`~/.app-controller`.

## Usage

``` Shell
# show app running status
apc show

# start all apps
apc start

# stop all apps
apc stop
```
