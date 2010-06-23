#!/bin/zsh

base_dir=$(dirname $0)
bitclust_dir=${base_dir}/../bitclust
rubydoc_dir=${base_dir}/../rubydoc

rurema_update=yes
index_update=yes
for argument in $*; do
    case "$argument" in
	"--no-rurema-update")
	    rurema_update=no
	    ;;
	"--no-index-update")
	    index_update=no
	    ;;
    esac
done

if [ "$rurema_update" = "yes" ]; then
    svn up -q ${rubydoc_dir}

    for version in 1.8.7 1.8.8 1.9.1 1.9.2; do
	ruby \
	    -I ${bitclust_dir}/lib \
	    ${bitclust_dir}/bin/bitclust.rb \
	    --database ${base_dir}/db-${version} \
	    init encoding=euc-jp version=${version}
	ruby \
	    -I ${bitclust_dir}/lib \
	    ${bitclust_dir}/bin/bitclust.rb \
	    --database ${base_dir}/db-${version} \
	    update --stdlibtree ${rubydoc_dir}/refm/api/src
	ruby \
	    -I ${bitclust_dir}/lib \
	    ${bitclust_dir}/bin/bitclust.rb \
	    --database ${base_dir}/db-${version} \
	    --capi \
	    update ${rubydoc_dir}/refm/capi/src/**/*.rd
	rm -rf ${base_dir}/public/${version}.{old,new}
	ruby \
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

if [ "$index_update" = "yes" ]; then
    rm -rf ${base_dir}/groonga-database
    (sleep 5; touch ${base_dir}/tmp/restart.txt) &

    ruby1.9.1 \
	${base_dir}/bin/bitclust-indexer \
	${base_dir}/db-*

    ruby1.9.1 ${base_dir}/bin/clear-cache
fi
