#!/bin/zsh

base_dir=$(dirname $0)
bitclust_dir=${base_dir}/../bitclust
rubydoc_dir=${base_dir}/../rubydoc

svn up -q ${rubydoc_dir}

for version in 1.8.7 1.8.8 1.9.1 1.9.2; do
    ruby \
    	-I ${bitclust_dir}/lib \
    	${bitclust_dir}/bin/bitclust.rb \
    	--database ${base_dir}/db-${version} \
    	init encoding=euc-jp version=${version} > /dev/null
    ruby \
    	-I ${bitclust_dir}/lib \
    	${bitclust_dir}/bin/bitclust.rb \
    	--database ${base_dir}/db-${version} \
    	update --stdlibtree ${rubydoc_dir}/refm/api/src > /dev/null
    rm -rf ${base_dir}/public/${version}.{old,new}
    ruby \
	-I ${base_dir}/lib \
	-I ${bitclust_dir}/lib \
	${base_dir}/bin/bitclust-generate-static-html \
	${bitclust_dir}/tools/bc-tohtmlpackage.rb \
	--database ${base_dir}/db-${version} \
	--outputdir ${base_dir}/public/${version}.new > /dev/null
    mv ${base_dir}/public/${version}{,.old}
    mv ${base_dir}/public/${version}{.new,}
    rm -rf ${base_dir}/public/${version}.old
done

ruby1.9.1 \
    -I../rroonga.19/lib \
    -I../rroonga.19/ext/groonga \
    ${base_dir}/bin/bitclust-indexer \
    ${base_dir}/db-*
