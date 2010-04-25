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

require 'webrick/httpstatus'

require 'rubygems'
require 'rack'

require 'rurema_search'
require 'rurema_search/groonga_searcher'


require 'rack/test'
require 'webrat'

Webrat.configure do |config|
  config.mode = :rack
end

module RuremaSearchTestUtils
  include Rack::Test::Methods
  include Webrat::Methods
  include Webrat::Matchers

  class << self
    def included(base)
      base.class_eval do
        setup :setup_tmp_dir
        teardown :teardown_tmp_dir
      end
    end

    def database
      @database ||= ensure_database
    end

    private
    def ensure_database
      database_dir = test_dir + "groonga-database"
      database_file = database_dir + "bitclust.db"
      dump_file = fixtures_dir + "dump.grn"
      if !database_file.exist? or database_file.mtime < dump_file.mtime
        FileUtils.rm_rf(database_dir.to_s)
        database_dir.mkpath
        command = "groonga -n #{database_file} < #{dump_file}"
        result = `#{command} 2>&1`
        # groonga not returns success status on success exit for now.
        # unless $?.success?
        #   FileUtils.rm_rf(database_dir.to_s)
        #   raise "failed to create test database: " +
        #           "<#{command}>: <#{$?.to_i}>: <#{result}>"
        # end
      end
      _database = RuremaSearch::GroongaDatabase.new
      _database.open(database_dir.to_s, "utf-8")
      _database
    end
  end

  def setup_tmp_dir
    FileUtils.mkdir_p(tmp_dir.to_s)
  end

  def teardown_tmp_dir
    FileUtils.rm_rf(tmp_dir.to_s)
  end

  def app
    RuremaSearch::GroongaSearcher.new(database, base_dir)
  end

  private
  def current_dom
    webrat.current_dom
  end

  def assert_response(code)
    assert_equal(resolve_status(code), resolve_status(webrat.response_code))
  end

  def resolve_status(code_or_message)
    messages = WEBrick::HTTPStatus::StatusMessage
    if code_or_message.is_a?(String)
      message = code_or_message
      [(messages.find {|key, value| value == message} || [])[0],
       message]
    else
      code = code_or_message
      [code, messages[code]]
    end
  end

  def database
    RuremaSearchTestUtils.database
  end

  module_function
  def test_dir
    @test_dir ||= Pathname(__FILE__).dirname
  end

  def base_dir
    @base_dir ||= test_dir.parent
  end

  def tmp_dir
    @tmp_dir ||= test_dir + "tmp"
  end

  def fixtures_dir
    @fixtures_dir ||= test_dir + "fixtures"
  end
end
