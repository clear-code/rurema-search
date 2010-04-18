#!/bin/zsh

base_dir=$(dirname $0)
bitclust_dir=${base_dir}/../bitclust
rubydoc_dir=${base_dir}/../rubydoc

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
    rm -rf ${base_dir}/public/${version}
    ruby \
	-I ${bitclust_dir}/lib \
	${bitclust_dir}/tools/bc-tohtmlpackage.rb \
	--database ${base_dir}/db-${version} \
	--outputdir ${base_dir}/public/${version}
done
