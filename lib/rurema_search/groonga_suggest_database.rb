# Copyright (c) 2011 Kouhei Sutou <kou@clear-code.com>
#
# License: LGPLv3+

require 'shellwords'
require 'json'
require 'groonga'

module RuremaSearch
  class GroongaSuggestDatabase
    def initialize
      @database = nil
      @dataset_name = "rurema"
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

    def register_keyword(keyword)
      return if keyword.nil? or keyword.empty?
      id = next_id
      values = []
      patterns = keyword_input_patterns(keyword)
      patterns.each do |pattern|
        now = Time.now
        timestamp = now.sec * 1000 + now.usec
        value = {
          "item" => pattern,
          "sequence" => id,
          "time" => timestamp,
        }
        values.last["type"] = "submit" if pattern == keyword
        values << value
      end
      @context.send("load " +
                    "--table #{table_name('event')} " +
                    "--each 'suggest_preparer(_id, type, item, " +
                    "sequence, time, #{table_name('pair')})'")
      @context.send(JSON.generate(values))
      @context.receive

      @context.send("load --table #{table_name('item')}")
      value = {
        "_key" => keyword,
        "boost" => 100,
      }
      @context.send(JSON.generate([value]))
      @context.receive
    end

    def register_related_keywords(keyword, related_keywords)
      return if keyword.nil? or keyword.empty?
      id = next_id
      values = []
      related_keywords.each do |related_keyword|
        next if related_keyword.empty?
        now = Time.now
        timestamp = now.sec * 1000 + now.usec
        value = {
          "item" => "#{keyword} #{related_keyword}",
          "sequence" => id,
          "time" => timestamp,
          "type" => "submit",
        }
        values << value
      end
      return if values.empty?
      @context.send("load " +
                    "--table event_#{@dataset_name} " +
                    "--each 'suggest_preparer(_id, type, item, " +
                    "sequence, time, pair_#{@dataset_name})'")
      @context.send(JSON.generate(values))
      @context.receive
    end

    def suggest(query)
      @context.send("/d/suggest?" +
                    "table=item_#{@dataset_name}&" +
                    "column=kana&" +
                    "limit=20&" +
                    "types=complete|suggest|correct&" +
                    "query=#{Rack::Utils.escape(query)}")
      id, json = @context.receive
      normalized_suggestions = {}
      JSON.parse(json).each do |key, value|
        normalized_suggestions[key] = normalize_suggest_entries(value)
      end
      normalized_suggestions
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
      command = "/tmp/local/bin/groonga-suggest-create-dataset #{escaped_path} rurema"
      result = `#{command}`
      unless $?.success?
        raise "failed to create suggest dataset: <#{command}>: <#{result}>"
      end

      @database = @context.open_database(path)
      Groonga::Schema.define(:context => @context) do |schema|
        schema.remove_table("bigram")

        schema.create_table("bigram_alphabet",
                            :type => :patricia_trie,
                            :key_type => "ShortText",
                            :default_tokenizer => "TokenBigramSplitSymbolAlphaDigit",
                            :key_normalize => true) do |table|
          table.index("item_#{@dataset_name}._key")
        end
      end
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
      keyword.chars.to_a.combination(keyword.size - 1).each do |chars|
        patterns << chars.join("")
        patterns << keyword
      end
      partial_keyword = ""
      keyword.each_char do |char|
        partial_keyword << char
        patterns << partial_keyword.dup
      end
      patterns
    end

    def table_name(name)
      "#{name}_#{@dataset_name}"
    end
  end
end
