# -*- ruby -*-
#
# Copyright (C) 2010  Kouhei Sutou <kou@clear-code.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

Encoding.default_external = "utf-8"

require 'pathname'

base_dir = Pathname.new(__FILE__).dirname.cleanpath.realpath
lib_dir = base_dir + "lib"

bitclust_dir = base_dir.parent + "bitclust"
bitclust_lib_dir = bitclust_dir + "lib"
rroonga_dir = base_dir.parent + "rroonga.19"
rroonga_lib_dir = rroonga_dir + "lib"
rroonga_ext_dir = rroonga_dir + "ext" + "groonga"

$LOAD_PATH.unshift(bitclust_lib_dir.to_s)
$LOAD_PATH.unshift(rroonga_ext_dir.to_s)
$LOAD_PATH.unshift(rroonga_lib_dir.to_s)
$LOAD_PATH.unshift(lib_dir.to_s)

require 'rurema_search'
require 'rurema_search/groonga_searcher'

database = RuremaSearch::GroongaDatabase.new
database.open((base_dir + "groonga-database").to_s, "utf-8")

environment = ENV["RACK_ENV"] || "development"

searcher_options = {}

use Rack::CommonLogger
use Rack::Runtime
case environment
when "development"
  class DirectoryIndex
    def initialize(app, options={})
      @app = app
      @urls = options[:urls]
    end

    def call(env)
      path = env["PATH_INFO"]
      can_serve = @urls.any? { |url| path.index(url) == 0 }
      env["PATH_INFO"] += "index.html" if can_serve and /\/\z/ =~ path
      @app.call(env)
    end
  end

  urls = ["/favicon.", "/css/", "/images/", "/js/", "/1.8.", "/1.9."]
  use DirectoryIndex, :urls => urls
  use Rack::Static, :urls => urls, :root => (base_dir + "public").to_s

  use Rack::ShowExceptions
when "production"
  smtp_configuration_file = base_dir + "smtp.yaml"
  if smtp_configuration_file.exist?
    require 'yaml'
    searcher_options[:smtp] = YAML.load(smtp_configuration_file.read)
  end
end

use Rack::Lint
run RuremaSearch::GroongaSearcher.new(database, base_dir.to_s, searcher_options)
