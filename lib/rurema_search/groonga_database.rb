# Copyright (c) 2010 Kouhei Sutou <kou@clear-code.com>
#
# License: LGPLv3+

require 'groonga'

module RuremaSearch
  class GroongaDatabase
    def initialize
      @context = nil
      @database = nil
      check_availability
    end

    def available?
      @available
    end

    def open(base_path, encoding)
      reset_context(encoding)
      path = File.join(base_path, "bitclust.db")
      if File.exist?(path)
        @database = @context.open_database(path)
        populate_schema
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

    def reopen
      base_path = File.dirname(@database.path)
      encoding = @database.encoding
      close
      open(base_path, encoding)
    end

    def purge
      path = @database.path
      encoding = @database.encoding
      @database.remove
      directory = File.dirname(path)
      FileUtils.rm_rf(directory)
      FileUtils.mkdir_p(directory)
      reset_context(encoding)
      populate(path)
    end

    def close
      @database.close
      @database = nil
      @context.close
      @context = nil
    end

    def closed?
      @database.nil? or @database.closed?
    end

    def names
      @context["Names"]
    end

    def entries
      @context["Entries"]
    end

    def specs
      @context["Specs"]
    end

    def classes
      @context["Classes"]
    end

    def modules
      @context["Modules"]
    end

    def objects
      @context["Objects"]
    end

    def libraries
      @context["Libraries"]
    end

    def singleton_methods
      @context["SingletonMethods"]
    end

    def instance_methods
      @context["InstanceMethods"]
    end

    def module_functions
      @context["ModuleFunctions"]
    end

    def constants
      @context["Constants"]
    end

    def special_variables
      @context["SpecialVariables"]
    end

    def versions
      @context["Versions"]
    end

    def purge_old_records(base_time)
      old_entries = entries.select do |record|
        record.last_modified < base_time
      end
      old_entries.each do |record|
        real_record = record.key
        real_record.delete
      end
    end

    def push_memory_pool(&block)
      @context.push_memory_pool(&block)
    end

    private
    def check_availability
      begin
        require 'groonga'
        @available = true
      rescue LoadError
        @available = false
      end
    end

    def reset_context(encoding)
      @context.close if @context
      @context = Groonga::Context.new(:encoding => encoding)
    end

    def populate(path)
      @database = @context.create_database(path)
      populate_schema
    end

    def populate_schema
      Groonga::Schema.define(:context => @context) do |schema|
        schema.create_table("Names",
                            :type => :patricia_trie,
                            :key_type => "ShortText") do |table|
        end

        schema.create_table("LocalNames",
                            :type => :patricia_trie,
                            :key_type => "ShortText") do |table|
        end

        schema.create_table("Types",
                            :type => :hash,
                            :key_type => "ShortText") do |table|
        end

        schema.create_table("Versions",
                            :type => :patricia_trie,
                            :key_type => "ShortText") do |table|
        end

        schema.create_table("Visibilities",
                            :type => :hash,
                            :key_type => "ShortText") do |table|
        end

        schema.create_table("Classes",
                            :type => :patricia_trie,
                            :key_type => "ShortText") do |table|
          table.reference("type", "Types")
        end

        schema.create_table("NormalizedClasses",
                            :type => :patricia_trie,
                            :key_type => "ShortText",
                            :key_normalize => true) do |table|
        end

        schema.create_table("Modules",
                            :type => :patricia_trie,
                            :key_type => "ShortText") do |table|
          table.reference("type", "Types")
        end

        schema.create_table("NormalizedModules",
                            :type => :patricia_trie,
                            :key_type => "ShortText",
                            :key_normalize => true) do |table|
        end

        schema.create_table("Objects",
                            :type => :patricia_trie,
                            :key_type => "ShortText") do |table|
          table.reference("type", "Types")
        end

        schema.create_table("NormalizedObjects",
                            :type => :patricia_trie,
                            :key_type => "ShortText",
                            :key_normalize => true) do |table|
        end

        schema.create_table("Libraries",
                            :type => :patricia_trie,
                            :key_type => "ShortText") do |table|
          table.reference("type", "Types")
        end

        schema.create_table("SingletonMethods",
                            :type => :hash,
                            :key_type => "ShortText") do |table|
        end

        schema.create_table("InstanceMethods",
                            :type => :hash,
                            :key_type => "ShortText") do |table|
        end

        schema.create_table("ModuleFunctions",
                            :type => :hash,
                            :key_type => "ShortText") do |table|
        end

        schema.create_table("Constants",
                            :type => :hash,
                            :key_type => "ShortText") do |table|
        end

        schema.create_table("SpecialVariables",
                            :type => :hash,
                            :key_type => "ShortText") do |table|
        end

        schema.create_table("Entries",
                            :type => :hash,
                            :key_type => "ShortText") do |table|
          table.reference("name", "Names")
          table.reference("local_name", "LocalNames")
          table.short_text("name_raw")
          table.short_text("local_name_raw")
          table.short_text("label")
          table.text("document")
          table.text("signature")
          table.text("summary")
          table.text("description")
          table.reference("type", "Types")
          table.reference("class", "Classes")
          table.reference("normalized_class", "NormalizedClasses")
          table.reference("module", "Modules")
          table.reference("normalized_module", "NormalizedModules")
          table.reference("object", "Objects")
          table.reference("normalized_object", "NormalizedObjects")
          table.reference("library", "Libraries")
          table.reference("version", "Versions")
          table.reference("visibility", "Visibilities")
          table.reference("related_names", "Names", :type => :vector)
          table.time("last_modified")
        end

        schema.create_table("Specs",
                            :type => :patricia_trie,
                            :key_type => "ShortText") do |table|
          table.reference("type", "Types")
        end

        schema.create_table("Bigram",
                            :type => :patricia_trie,
                            :key_type => "ShortText",
                            :default_tokenizer => "TokenBigram",
                            :key_normalize => true) do |table|
          table.index("Entries.document")
          table.index("Entries.summary")
          table.index("Entries.description")
        end

        schema.create_table("BigramAlphabet",
                            :type => :patricia_trie,
                            :key_type => "ShortText",
                            :default_tokenizer => "TokenBigramSplitSymbolAlphaDigit",
                            :key_normalize => true) do |table|
          table.index("Entries.name_raw")
          table.index("Entries.local_name_raw")
          table.index("Entries.label")
          table.index("Entries.signature")
        end

        schema.change_table("Names") do |table|
          table.index("Entries.name")
        end

        schema.change_table("LocalNames") do |table|
          table.index("Entries.local_name")
        end

        schema.change_table("Versions") do |table|
          table.index("Entries.version")
        end

        schema.change_table("Classes") do |table|
          table.index("Entries.class")
        end

        schema.change_table("NormalizedClasses") do |table|
          table.index("Entries.normalized_class")
        end

        schema.change_table("Modules") do |table|
          table.index("Entries.module")
        end

        schema.change_table("NormalizedModules") do |table|
          table.index("Entries.normalized_module")
        end

        schema.change_table("Objects") do |table|
          table.index("Entries.object")
        end

        schema.change_table("NormalizedObjects") do |table|
          table.index("Entries.normalized_object")
        end

        schema.change_table("Libraries") do |table|
          table.index("Entries.library")
        end
      end
    end
  end
end
