#!/bin/sh

base_dir=$(cd "$(dirname "$0")" && pwd)
: ${RUBY:=ruby}

run()
{
    "$@"
    if test $? -ne 0; then
        echo "Failed $@"
        exit 1
    fi
}

set -x

run ${RUBY} -S gem install rack pkg-config

run cd ${base_dir}/..
run git clone https://github.com/rurema/bitclust.git bitclust
run git clone https://github.com/rurema/doctree.git doctree

run git clone https://github.com/groonga/groonga.git
run cd groonga
run ./autogen.sh
run ./configure \
    --prefix=${base_dir}/local \
    --disable-document \
    --disable-groonga-httpd
run make
run make install
run cd -

run git clone https://github.com/ranguba/rroonga.git
run cd rroonga
run export PKG_CONFIG_PATH=${base_dir}/local/lib/pkgconfig
run ${RUBY} extconf.rb
run make
run cd -

run git clone https://github.com/ranguba/racknga.git

run cd rurema-search
run ./update.sh
