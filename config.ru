# -*- ruby -*-

require 'pathname'

base_dir = Pathname.new(__FILE__).dirname.cleanpath.realpath
lib_dir = base_dir + "lib"

bitclust_dir = base_dir.parent + "bitclust"
bitclust_lib_dir = bitclust_dir + "lib"

$LOAD_PATH.unshift(bitclust_lib_dir.to_s)
$LOAD_PATH.unshift(lib_dir.to_s)

require 'rurema_search'
require 'rurema_search/groonga_searcher'

database = RuremaSearch::GroongaDatabase.new
database.open((base_dir + "groonga-database").to_s, "utf-8")
run RuremaSearch::GroongaSearcher.new(database, base_dir.to_s)
