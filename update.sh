#!/bin/zsh

for version in 1.8.7 1.8.8 1.9.1 1.9.2; do
    ruby \
	-I ~/work/ruby/bitclust/lib \
	-I ~/work/ruby/rroonga/lib \
	-I ~/work/ruby/rroonga/ext \
	~/work/ruby/bitclust/bin/bitclust.rb \
	--database ~/work/ruby/rurema-search/db-${version} \
	init encoding=euc-jp version=${version}
    ruby \
	-I ~/work/ruby/bitclust/lib \
	-I ~/work/ruby/rroonga/lib \
	-I ~/work/ruby/rroonga/ext \
	~/work/ruby/bitclust/bin/bitclust.rb \
	--database ~/work/ruby/rurema-search/db-${version} \
	update --stdlibtree ~/work/ruby/rubydoc/refm/api/src
done
