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

run cd ${base_dir}/..
run git clone https://github.com/rurema/bitclust.git bitclust
run git clone https://github.com/rurema/doctree.git doctree

run cd rurema-search

run bundle install
run bundle exec ./update.sh
