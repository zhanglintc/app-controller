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
# view detail of one given pid
apc view 10389

# show app running status
apc show

# start all apps
apc start

# start given app
apc start 0

# stop all apps
apc stop

# stop given app
apc stop 0

# restart all apps
apc restart

# restart given app
apc restart 0

# add an app to control list
apc add foo.bar

# show control list
apc list

# edit control list(try vim/vi/nano)
apc edit

# del an app from control list
apc del 0
```
