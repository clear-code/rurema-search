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

use Rack::CommonLogger
use Rack::ShowExceptions
use Rack::Runtime
use Rack::Static, :urls => ["/favicon.ico", "/css/", "/js/", "/1.8.", "/1.9"],
                  :root => (base_dir + "public").to_s

use Rack::Lint
run RuremaSearch::GroongaSearcher.new(database, base_dir.to_s)
