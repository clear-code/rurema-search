#!/bin/sh

base_dir=$(dirname $0)
bitclust_dir=${base_dir}/../bitclust
rubydoc_dir=${base_dir}/../rubydoc

update_rurema=yes
update_index=yes
reset_index=no
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
	"--no-clear-cache")
	    clear_cache=no
	    ;;
    esac
done

if [ "$update_rurema" = "yes" ]; then
    svn up -q ${rubydoc_dir}

    for version in 1.8.7 1.9.1 1.9.2; do
	ruby1.8 \
	    -I ${bitclust_dir}/lib \
	    ${bitclust_dir}/bin/bitclust.rb \
	    --database ${base_dir}/db-${version} \
	    init encoding=euc-jp version=${version}
	ruby1.8 \
	    -I ${bitclust_dir}/lib \
	    ${bitclust_dir}/bin/bitclust.rb \
	    --database ${base_dir}/db-${version} \
	    update --stdlibtree ${rubydoc_dir}/refm/api/src
	ruby1.8 \
	    -I ${bitclust_dir}/lib \
	    ${bitclust_dir}/bin/bitclust.rb \
	    --database ${base_dir}/db-${version} \
	    --capi \
	    update ${rubydoc_dir}/refm/capi/src/**/*.rd
	rm -rf ${base_dir}/public/${version}.{old,new}
	ruby1.8 \
	    -I ${base_dir}/lib \
	    -I ${bitclust_dir}/lib \
	    ${base_dir}/bin/bitclust-generate-static-html \
	    ${bitclust_dir}/tools/bc-tohtmlpackage.rb \
	    --quiet \
	    --fs-casesensitive \
	    --database ${base_dir}/db-${version} \
	    --outputdir ${base_dir}/public/${version}.new
	mv ${base_dir}/public/${version}{,.old}
	mv ${base_dir}/public/${version}{.new,}
	rm -rf ${base_dir}/public/${version}.old
    done
fi

if [ "$update_index" = "yes" ]; then
    indexer_arguments=
    if [ "$reset_index" = "yes" ]; then
	rm -rf ${base_dir}/groonga-database
	indexer_arguments="${indexer_arguments} --reset"
    fi
    ruby1.9.1 \
	${base_dir}/bin/bitclust-indexer \
	${indexer_arguments} \
	${base_dir}/db-*
fi

if [ "$clear_cache" = "yes" ]; then
    ruby1.9.1 ${base_dir}/bin/rurema-search-clear-cache
fi
