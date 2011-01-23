# Copyright (c) 2011 Kouhei Sutou <kou@clear-code.com>
#
# License: LGPLv3+

require 'shellwords'
require 'groonga'

module RuremaSearch
  class GroongaSuggestDatabase
    def initialize
      @database = nil
      @dataset_name = "rurema"
    end

    def available?
      @available
    end

    def open(base_path)
      path = File.join(base_path, "suggest.db")
      unless File.exist?(path)
        FileUtils.mkdir_p(base_path)
        populate(path)
      end
      @context = Groonga::Context.new(:encoding => :utf8)
      @database = @context.open_database(path)
      if block_given?
        begin
          yield(self)
        ensure
          close unless closed?
        end
      end
    end

    def purge
      path = @database.path
      encoding = @database.encoding
      @database.remove
      directory = File.dirname(path)
      FileUtils.rm_rf(directory)
      FileUtils.mkdir_p(directory)
      populate(path)
      @context = Groonga::Context.new(:encoding => encoding)
    end

    def close
      @database.close
      @database = nil
    end

    def closed?
      @database.nil? or @database.closed?
    end

    def items
      @context["item_#{@dataset_name}"]
    end

    def pairs
      @context["pair_#{@dataset_name}"]
    end

    def sequences
      @context["sequence_#{@dataset_name}"]
    end

    def events
      @context["event_#{@dataset_name}"]
    end

    private
    def populate(path)
      escaped_path = Shellwords.escape(path)
      command = "groonga-suggest-create-dataset #{escaped_path} rurema"
      result = `#{command}`
      unless $?.success?
        raise "failed to create suggest dataset: <#{command}>: <#{result}>"
      end
    end
  end
end
