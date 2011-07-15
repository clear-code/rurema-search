#!/bin/sh

base_dir=$(dirname $0)
: ${RUBY:=ruby1.9.1}

run()
{
    "$@"
    if test $? -ne 0; then
        echo "Failed $@"
        exit 1
    fi
}

set -x

run ${RUBY} -S gem install --user-install rack

run cd ${base_dir}/..
run svn co http://jp.rubyist.net/svn/rurema/bitclust/trunk bitclust
run svn co http://jp.rubyist.net/svn/rurema/doctree/trunk rubydoc

run git clone git://github.com/groonga/groonga.git
run cd groonga
run ./autogen.sh
run ./configure --prefix=${base_dir}/local
run make
run make install
run cd -

run git clone git://github.com/ranguba/rroonga.git
run cd rroonga
run PKG_CONFIG_PATH=${base_dir}/lib/pkgconfig ${RUBY} extconf.rb
run make
run cd -

run git clone git://github.com/ranguba/racknga.git

run cd rurema-search
run ./update.sh
