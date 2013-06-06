#!/bin/sh

run()
{
    "$@"
    if test $? -ne 0; then
	echo "Failed $@"
	exit 1
    fi
}

if [ $# -ne 1 ]; then
    echo "Usage: $0 HOST_NAME"
    echo " e.g.: $0 rurema.clear-code.com"
    exit 1
fi

host_name=$1
user=rurema

if ! id $user > /dev/null 2>&1; then
    run adduser --system --group --gecos "Rurema Search" $user
    run sudo -u rurema -H sh -c "echo root > ~rurema/.forward"
fi

groonga_list=/etc/apt/sources.list.d/groonga.list
if [ ! -f $groonga_list ]; then
    cat <<EOF > $groonga_list
deb http://packages.groonga.org/debian/ squeeze main
deb-src http://packages.groonga.org/debian/ squeeze main
EOF
    run apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 1C837F31
fi

run apt-get update
run apt-get install -y aptitude

run aptitude -V -r -D install -y \
    sudo subversion git build-essential \
    groonga libgroonga-dev \
    ruby rubygems ruby1.9.1-full \
    apache2 apache2-threaded-dev libcurl4-gnutls-dev \
    munin-node

run gem1.9.1 install --no-ri --no-rdoc rack rroonga racknga passenger

passenger_root=$(dirname $(dirname $(gem1.9.1 which phusion_passenger)))
passenger_module=$passenger_root/ext/apache2/mod_passenger.so
if [ ! -f $passenger_module ]; then
    (echo 1; echo) | run /var/lib/gems/1.9.1/bin/passenger-install-apache2-module
fi

apache_module_conf_d=/etc/apache2/mods-available
apache_passenger_module_conf=$apache_module_conf_d/passenger.conf
apache_passenger_module_load=$apache_module_conf_d/passenger.load
if [ ! -f $apache_passenger_module_load ]; then
    run cat <<EOF > $apache_passenger_module_load
LoadModule passenger_module ${passenger_module}
EOF
fi
if [ ! -f $apache_passenger_module_conf ]; then
    run cat <<EOF > $apache_passenger_module_conf
PassengerRoot ${passenger_root}
PassengerRuby $(which ruby1.9.1)

PassengerMaxRequests 100
EOF
fi
if [ ! -f /etc/apache2/mods-enabled/passenger.conf ]; then
    run a2enmod passenger
fi

apache_rurema_site_conf=/etc/apache2/sites-available/rurema
if [ ! -f $apache_rurema_site_conf ]; then
    run cat <<EOF > $apache_rurema_site_conf
<VirtualHost *:80>
  ServerName $host_name
  DocumentRoot /home/$user/rurema-search/public
  <Directory /home/$user/rurema-search/public>
     AllowOverride all
     Options -MultiViews
  </Directory>

  ErrorLog \${APACHE_LOG_DIR}/rurema_error.log
  CustomLog \${APACHE_LOG_DIR}/rurema_access.log combined

  AllowEncodedSlashes On
  AcceptPathInfo On
</VirtualHost>
EOF
    run a2ensite rurema
    run service apache2 restart
fi

munin_plugin_conf=/etc/munin/plugin-conf.d/rurema-search
if [ ! -f $munin_plugin_conf ]; then
    run cat <<EOF > $munin_plugin_conf
[passenger_*]
  user root
  env.ruby /usr/bin/ruby1.9.1
  env.GEM_HOME /var/lib/gems/1.9.1
EOF
    munin-node-configure \
	--libdir $(dirname $(dirname $(gem1.9.1 which racknga)))/munin/plugins \
	--shell | sh
    run service munin-node restart
fi


cd ~rurema

if [ -d rurema-search ]; then
    (cd rurema-search && run sudo -u rurema -H git pull --rebase)
else
    run sudo -u rurema -H git clone \
	https://github.com/kou/rurema-search.git rurema-search
fi

if [ -d bitclust ]; then
    (cd bitclust && run sudo -u rurema -H git pull --rebase)
else
    run sudo -u rurema -H git clone \
        git://github.com/rurema/bitclust.git bitclust
fi

if [ -d rubydoc ]; then
    (cd rubydoc && run sudo -u rurema -H git pull --rebase)
else
    run sudo -u rurema -H git clone \
        git://github.com/rurema/doctree.git rubydoc
fi

cd rurema-search
if [ ! -f production.yaml ]; then
    run cat <<EOF > production.yaml
use_cache:
  true
EOF
fi

echo "@daily nice /home/$user/rurema-search/update.sh" | run crontab -u $user -

run sudo -u rurema -H nice ./update.sh
