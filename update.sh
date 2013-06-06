#!/bin/zsh

base_dir=$(cd "$(dirname "$0")" && pwd)
: ${RUBY:=ruby1.9.1}
bitclust_dir=${base_dir}/../bitclust
rubydoc_dir=${base_dir}/../rubydoc

PATH=${base_dir}/local/bin:$PATH

update_rurema=yes
update_index=yes
reset_index=no
reset_suggest=no
load_data=yes
clear_cache=yes
for argument in $*; do
    case "$argument" in
	"--no-update-rurema")
	    update_rurema=no
	    ;;
	"--no-update-index")
	    update_index=no
	    ;;
	"--reset-index")
	    reset_index=yes
	    ;;
	"--reset-suggest")
	    reset_suggest=yes
	    ;;
	"--no-load-data")
	    load_data=no
	    ;;
	"--no-clear-cache")
	    clear_cache=no
	    ;;
    esac
done

update_rurema()
{
    local version=$1

    nice ${RUBY} \
	-I ${bitclust_dir}/lib \
	${bitclust_dir}/bin/bitclust \
	--database ${base_dir}/db-${version} \
	init encoding=utf-8 version=${version}
    nice ${RUBY} \
	-I ${bitclust_dir}/lib \
	${bitclust_dir}/bin/bitclust \
	--database ${base_dir}/db-${version} \
	update --stdlibtree ${rubydoc_dir}/refm/api/src
    nice ${RUBY} \
	-I ${bitclust_dir}/lib \
	${bitclust_dir}/bin/bitclust \
	--database ${base_dir}/db-${version} \
	--capi \
	update ${rubydoc_dir}/refm/capi/src/**/*.rd
    rm -rf ${base_dir}/public/${version}.{old,new}
    nice ${RUBY} \
	-I ${base_dir}/lib \
	-I ${bitclust_dir}/lib \
	${base_dir}/bin/bitclust-generate-static-html \
	${bitclust_dir}/tools/bc-tohtmlpackage.rb \
	--quiet \
	--fs-casesensitive \
	--database ${base_dir}/db-${version} \
	--outputdir ${base_dir}/public/${version}.new \
	--catalog ${bitclust_dir}/data/bitclust/catalog
    mv ${base_dir}/public/${version}{,.old}
    mv ${base_dir}/public/${version}{.new,}
    rm -rf ${base_dir}/public/${version}.old
}

if [ "$update_rurema" = "yes" ]; then
    (cd ${rubydoc_dir} && git pull --rebase)

    for version in 1.8.7 1.9.3 2.0.0; do
	update_rurema $version
    done
    wait
fi

if [ "$update_index" = "yes" ]; then
    reset_argument=
    load_data_argument=
    if [ "$reset_index" = "yes" ]; then
	rm -rf ${base_dir}/groonga-database
	rm -rf ${base_dir}/var/lib/suggest
	touch ${base_dir}/tmp/restart.txt
	reset_argument="--reset"
    fi
    if [ "$reset_suggest" = "yes" ]; then
	rm -rf ${base_dir}/var/lib/suggest
	touch ${base_dir}/tmp/restart.txt
    fi
    if [ "$load_data" != "yes" ]; then
	load_data_argument="--no-load-data"
    fi
    nice ${RUBY} \
	${base_dir}/bin/bitclust-indexer \
	${reset_argument} \
	${load_data_argument} \
	${base_dir}/db-*
fi

if [ "$clear_cache" = "yes" ]; then
    nice ${RUBY} ${base_dir}/bin/rurema-search-clear-cache
fi

touch ${base_dir}/tmp/restart.txt
