# Copyright (c) 2011 Kouhei Sutou <kou@clear-code.com>
#
# License: LGPLv3+

require 'shellwords'
require 'json'
require 'groonga'

module RuremaSearch
  class GroongaSuggestDatabase
    DATASET = "rurema"

    def initialize
      @database = nil
      @dataset_name = DATASET
      @id = 0
    end

    def open(base_path)
      @context = Groonga::Context.new(:encoding => :utf8)
      path = File.join(base_path, "suggest.db")
      if File.exist?(path)
        @database = @context.open_database(path)
      else
        FileUtils.mkdir_p(base_path)
        populate(path)
      end
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
      @context = Groonga::Context.new(:encoding => encoding)
      populate(path)
    end

    def register_keyword(keyword, related_keywords)
      return if keyword.nil? or keyword.empty?
      related_keywords = related_keywords.reject do |related_keyword|
        related_keyword.empty?
      end

      event_values = []
      event_values.concat(generate_input_event_values(next_id, keyword))
      related_keywords.each do |related_keyword|
        combined_keyword = [keyword, related_keyword].join(" ")
        event_values.concat(generate_input_event_values(next_id,
                                                        combined_keyword))
      end
      @context.send("load " +
                    "--table #{table_name('event')} " +
                    "--each 'suggest_preparer(_id, type, item, " +
                    "sequence, time, #{table_name('pair')})'")
      @context.send(JSON.generate(event_values))
      @context.receive

      item_values = []
      item_values << {"_key" => keyword, "kana" => keyword}
      related_keywords.each do |related_keyword|
        item_values << {"_key" => related_keyword, "kana" => related_keyword}
      end
      @context.send("load --table #{table_name('item')}")
      @context.send(JSON.generate(item_values))
      @context.receive
    end

    def corrections(query, options={})
      suggest("correct", query, options)
    end

    def suggestions(query, options={})
      suggest("suggest", query, options)
    end

    def completions(query, options={})
      suggest("complete", query, options)
    end

    def close
      @database.close
      @database = nil
    end

    def closed?
      @database.nil? or @database.closed?
    end

    private
    def populate(path)
      escaped_path = Shellwords.escape(path)
      command = "groonga-suggest-create-dataset #{escaped_path} rurema"
      result = `#{command}`
      unless $?.success?
        raise "failed to create suggest dataset: <#{command}>: <#{result}>"
      end

      @database = @context.open_database(path)
    end

    def normalize_suggest_entries(entries)
      n_netries, headers, *values = entries
      values.collect do |key, score|
        {:key => key, :score => score}
      end
    end

    def next_id
      @id += 1
    end

    def keyword_input_patterns(keyword)
      patterns = []
      partial_keyword = ""
      keyword.each_char do |char|
        partial_keyword << char
        patterns << partial_keyword.dup
      end
      patterns
    end

    def generate_input_event_values(id, keyword)
      values = []
      now = Time.now
      time_stamp = now.to_i * 1_000_000 + now.usec
      keyword_input_patterns(keyword).each do |partial_keyword|
        value = {
          "item" => partial_keyword,
          "sequence" => id,
          "time" => time_stamp,
        }
        values << value
        time_stamp += 1
      end
      values << {
        "item" => keyword,
        "kana" => keyword,
        "sequence" => id,
        "time" => time_stamp,
        "type" => "submit"
      }
      values
    end

    def table_name(name)
      "#{name}_#{@dataset_name}"
    end

    def suggest(type, query, options={})
      @context.send("/d/suggest?" +
                    "table=item_#{@dataset_name}&" +
                    "column=kana&" +
                    "limit=#{(options[:limit] || 10).to_i}&" +
                    "types=#{Rack::Utils.escape(type)}&" +
                    "threshold=1&" +
                    "query=#{Rack::Utils.escape(query)}")
      id, json = @context.receive
      normalize_suggest_entries(JSON.parse(json)[type])
    end
  end
end
