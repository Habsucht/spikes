#!/bin/bash

DEPENDENCIES='wget curl jq tar'

if [ -x "$(command -v apk)" ];then 
  apk add $DEPENDENCIES
elif [ -x "$(command -v apt-get)" ];then
  apt-get install -y $DEPENDENCIES
elif [ -x "$(command -v dnf)" ];then 
  dnf install -y $DEPENDENCIES
elif [ -x "$(command -v zypper)" ];then 
  zypper install -y $DEPENDENCIES
else echo "FAILED TO INSTALL PACKAGE: Package manager not found. You must manually install: $DEPENDENCIES">&2; 
fi

###############################################

if [[ -z $1 ]];then

    INSTALL=0

    ###############################################

    echo "----------------------------------------------------"
    CURRENT_VERSION="$(curl https://api.github.com/repos/prometheus/node_exporter/releases | jq .[0].tag_name | tr -d '"' | tr -d 'v')"

    echo "Current version node_exporter: $CURRENT_VERSION" 

    echo "----------------------------------------------------"
    echo "Checking installed version"
    echo "---"

    if test -e /usr/sbin/node_exporter;then
      INSTALLED_VERSION="$(/usr/sbin/node_exporter --version | head -n1 | awk ' {print $3} ')"
      echo "Installed version: $INSTALLED_VERSION"
    else
      INSTALLED_VERSION=0
      echo "node_exporter not installed"
    fi

    ###############################################
    #version comparison

    if (( $( echo $CURRENT_VERSION | awk -F '.' ' {print $1} ') > $( echo $INSTALLED_VERSION | awk -F '.' ' {print $1} ') ));then
      INSTALL=1
    elif (( $( echo $CURRENT_VERSION | awk -F '.' ' {print $1} ') == $( echo $INSTALLED_VERSION | awk -F '.' ' {print $1} ') ));then
      if (( $( echo $CURRENT_VERSION | awk -F '.' ' {print $2} ') > $( echo $INSTALLED_VERSION | awk -F '.' ' {print $2} ') ));then
        INSTALL=1
      elif (( $( echo $CURRENT_VERSION | awk -F '.' ' {print $2} ') == $( echo $INSTALLED_VERSION | awk -F '.' ' {print $2} ') ));then
        if (( $( echo $CURRENT_VERSION | awk -F '.' ' {print $3} ') > $( echo $INSTALLED_VERSION | awk -F '.' ' {print $3} ') ));then
          INSTALL=1
        fi
      fi
    fi
else
  INSTALL=1
  CURRENT_VERSION="$1"
fi

###############################################

echo "----------------------------------------------------"
echo "Checking initialization system"
echo "---"

if ls -l /sbin/init | egrep -i -q '(systemd)';then
  INIT="systemd"
  echo "Init: $INIT"
  if test -f /etc/systemd/system/node_exporter.service;then
    if (( $INSTALL == 1 ));then
      systemctl stop node_exporter
    fi
  else
    echo "Create systemd service"
    echo 'OPTIONS=""' > /etc/sysconfig/node_exporter
    echo '[Unit]
Description=Node Exporter
[Service]
User=root
EnvironmentFile=/etc/sysconfig/node_exporter
ExecStart=/usr/sbin/node_exporter $OPTIONS
[Install]
WantedBy=multi-user.target' > /etc/systemd/system/node_exporter.service
    chmod 755 /etc/systemd/system/node_exporter.service
    systemctl enable node_exporter
  fi
elif ls -l /sbin/init | egrep -i -q '(busybox)';then
  INIT="open-rc"
  echo "Init: $INIT" 
  if test -f /etc/init.d/node_exporter;then
    if (( $INSTALL == 1 ));then
      rc-service node_exporter stop
    fi
  else
    echo "Create open-rc service"
    echo '#!/sbin/openrc-run
description="node_exporter"
: ${NODE_PIDFILE:=/var/run/node_exporter.pid}
: ${NODE_USER:=root}
depend() {
        need net
        need localmount
        use dns
        after firewall
}
start() {
        ebegin "Starting node_exporter"
        start-stop-daemon --wait 1000 --background --start --exec \
                /usr/sbin/node_exporter \
                --user ${NODE_USER} \
                --make-pidfile --pidfile ${NODE_PIDFILE} \
                -- && \
        chown ${NODE_USER}:root ${NODE_PIDFILE}
        eend $?
}
stop() {
        ebegin "Stopping node_exporter"
        start-stop-daemon --wait 5000 --stop --exec \
                /usr/sbin/node_exporter \
                --user ${NODE_USER} \
                --pidfile ${NODE_PIDFILE} \
                -s SIGQUIT
        eend $?
}' > /etc/init.d/node_exporter
  chmod 755 /etc/init.d/node_exporter
  rc-update add node_exporter
  fi
else
  echo "Initialization system not defined"
  ls -l /sbin/init
fi
echo "----------------------------------------------------"

###############################################

if (( $INSTALL == 1 ));then

  wget https://github.com/prometheus/node_exporter/releases/download/v$CURRENT_VERSION/node_exporter-$CURRENT_VERSION.linux-amd64.tar.gz
  tar xvfz node_exporter-$CURRENT_VERSION.linux-amd64.tar.gz

  if test -f /usr/sbin/node_exporter;then
    rm /usr/sbin/node_exporter
  fi

  cp ./node_exporter-$CURRENT_VERSION.linux-amd64/node_exporter /usr/sbin/node_exporter

  echo "New installed version: $(/usr/sbin/node_exporter --version | head -n1 | awk ' {print $3} ')"

  rm -R ./node_exporter-$CURRENT_VERSION.linux-amd64*

else 
  echo "Already installed"
fi
echo "----------------------------------------------------"

###############################################

if  [ $INIT == "systemd" ];then
  systemctl start node_exporter
  systemctl status node_exporter
elif [ $INIT == "open-rc" ];then
  rc-service node_exporter start
  rc-service node_exporter status
fi
