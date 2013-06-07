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

require 'open-uri'
require 'webrick/httpstatus'

require 'rubygems'
require 'rack'

require 'rurema_search'
require 'rurema_search/groonga_searcher'

require 'rack/test'
require 'test/unit/capybara'

module RuremaSearchTestUtils
  include Rack::Test::Methods
  include Capybara::DSL

  class << self
    def included(base)
      base.class_eval do
        setup :setup_app
        setup :setup_tmp_dir
        teardown :teardown_tmp_dir

        setup :setup_host
      end
    end

    def database
      @database ||= ensure_database
    end

    def suggest_database
      @suggest_database ||= ensure_suggest_database
    end

    private
    def ensure_database
      updated = ensure_bitclust_database
      database_dir = test_dir + "groonga-database"
      database_file = database_dir + "bitclust.db"
      bitclust_database_dir = test_dir + "db-1.9.1"
      if !database_file.exist? or
          database_file.mtime < bitclust_database_dir.mtime
        FileUtils.rm_rf(database_dir.to_s)
        database_dir.mkpath
        ruby = File.join(RbConfig::CONFIG["bindir"],
                         RbConfig::CONFIG["ruby_install_name"])
        ruby << RbConfig::CONFIG["EXEEXT"]
        indexer = base_dir + "bin" + "bitclust-indexer"
        command = "#{ruby} #{indexer} "
        command << "--database #{database_dir} #{test_dir + 'db-*'}"
        print("creating database by '#{command}'...")
        result = `#{command} 2>&1`
        unless $?.success?
          FileUtils.rm_rf(database_dir.to_s)
          raise "failed to create test database: " +
                  "<#{command}>: <#{$?.to_i}>: <#{result}>"
        end
        puts "done."
      end
      _database = RuremaSearch::GroongaDatabase.new
      _database.open(database_dir.to_s, "utf-8")
      _database
    end

    def ensure_bitclust_database
      ensure_rubydoc
      rubydoc_dir = fixtures_dir + "rubydoc"
      source_dir = rubydoc_dir + "refm/api/src"
      ["1.8.7", "1.9.1"].each do |version|
        bitclust_database_dir = test_dir + "db-#{version}"
        if !bitclust_database_dir.exist? or
            bitclust_database_dir.mtime < rubydoc_dir.mtime
          system("bundle", "exec",
                 "bitclust", "--database", bitclust_database_dir.to_s,
                 "init", "encoding=utf-8", "version=#{version}")
          system("bundle", "exec",
                 "bitclust", "--database", bitclust_database_dir.to_s,
                 "update", "--stdlibtree", source_dir.to_s)
        end
      end
    end

    def ensure_rubydoc
      rubydoc_dir = fixtures_dir + "rubydoc"
      if rubydoc_dir.exist?
        system("git", "pull", "--rebase",
               :err => :out, :chdir => rubydoc_dir.to_s)
      else
        system("git", "clone", "--depth", "10",
               "git://github.com/rurema/doctree.git", rubydoc_dir.to_s,
               :err => :out)
      end
    end

    def ensure_bitclust_archive
      base_name = "ruby-refm-1.9.1-dynamic-20100629.tar.bz2"
      path = fixtures_dir + base_name
      fixtures_dir.mkpath unless fixtures_dir.exist?
      unless path.exist?
        url = "http://doc.ruby-lang.org/archives/201006/#{base_name}"
        print("downloading #{url}...")
        open(url, "rb") do |input|
          path.open("wb") do |output|
            output.print(input.read)
          end
        end
        puts("done.")
      end
      archive_dir = fixtures_dir + base_name.gsub(/\.tar\.bz2\z/, '')
      unless archive_dir.exist?
        unless system("tar", "xjf", path.to_s, "-C", fixtures_dir.to_s)
          raise "failed to extract #{path}."
        end
      end
      archive_dir
    end

    def ensure_suggest_database
      database_dir = test_dir + "suggest-database"
      _database = RuremaSearch::GroongaSuggestDatabase.new
      _database.open(database_dir.to_s)
      _database
    end
  end

  def setup_app
    Capybara.app = app
  end

  def setup_tmp_dir
    FileUtils.mkdir_p(tmp_dir.to_s)
  end

  def teardown_tmp_dir
    FileUtils.rm_rf(tmp_dir.to_s)
  end

  def setup_host
    header("Host", host)
  end

  def app
    RuremaSearch::GroongaSearcher.new(database, suggest_database, base_dir)
  end

  private
  def current_dom
    #webrat.current_dom
    nil
  end

  def assert_response(code)
    #assert_equal(resolve_status(code), resolve_status(webrat.response_code))
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

  def suggest_database
    RuremaSearchTestUtils.suggest_database
  end

  def host
    Capybara.default_host
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
