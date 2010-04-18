# Copyright (c) 2010 Kouhei Sutou <kou@clear-code.com>
#
# License: LGPLv3+

require 'groonga'

module RuremaSearch
  class GroongaDatabase
    def initialize
      @database = nil
      @use_view = false
      check_availability
    end

    def available?
      @available
    end

    def use_view?
      @use_view
    end

    def open(base_path, encoding)
      reset_context(encoding)
      path = File.join(base_path, "bitclust.db")
      if File.exist?(path)
        @database = Groonga::Database.open(path)
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
      reset_context(encoding)
      populate(path)
    end

    def close
      @database.close
      @database = nil
    end

    def closed?
      @database.nil? or @database.closed?
    end

    def entries
      @entries ||= Groonga["Entries"]
    end

    def specs
      @specs ||= Groonga["Specs"]
    end

    def classes
      @classes ||= Groonga["Classes"]
    end

    def modules
      @modules ||= Groonga["Modules"]
    end

    def objects
      @objects ||= Groonga["Objects"]
    end

    def singleton_methods
      @singleton_methods ||= Groonga["SingletonMethods"]
    end

    def instance_methods
      @instance_methods ||= Groonga["InstanceMethods"]
    end

    def module_functions
      @module_functions ||= Groonga["ModuleFunctions"]
    end

    def constants
      @constants ||= Groonga["Constants"]
    end

    def special_variables
      @special_variables ||= Groonga["SpecialVariables"]
    end

    def versions
      @versions ||= Groonga["Versions"]
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
      Groonga::Context.default_options = {:encoding => encoding}
      Groonga::Context.default = nil
    end

    def populate(path)
      @database = Groonga::Database.create(:path => path)
      populate_schema
    end

    def populate_schema
      Groonga::Schema.define do |schema|
        schema.create_table("Versions",
                            :type => :hash,
                            :key_type => "ShortText") do |table|
        end

        schema.create_table("Visibilities",
                            :type => :hash,
                            :key_type => "ShortText") do |table|
        end

        schema.create_table("Classes",
                            :type => :hash,
                            :key_type => "ShortText") do |table|
          table.short_text("name")
          table.text("document")
          table.reference("version", "Versions")
        end

        schema.create_table("Modules",
                            :type => :hash,
                            :key_type => "ShortText") do |table|
          table.short_text("name")
          table.text("document")
          table.reference("version", "Versions")
        end

        schema.create_table("Objects",
                            :type => :hash,
                            :key_type => "ShortText") do |table|
          table.short_text("name")
          table.text("document")
          table.reference("version", "Versions")
        end

        schema.create_table("SingletonMethods",
                            :type => :hash,
                            :key_type => "ShortText") do |table|
          table.short_text("name")
          table.short_text("local_names", :type => :vector)
          table.text("document")
          table.reference("class", "Classes")
          table.reference("module", "Modules")
          table.reference("object", "Objects")
          table.reference("version", "Versions")
          table.reference("visibility", "Visibilities")
        end

        schema.create_table("InstanceMethods",
                            :type => :hash,
                            :key_type => "ShortText") do |table|
          table.short_text("name")
          table.short_text("local_names", :type => :vector)
          table.text("document")
          table.reference("class", "Classes")
          table.reference("module", "Modules")
          table.reference("object", "Objects")
          table.reference("version", "Versions")
          table.reference("visibility", "Visibilities")
        end

        schema.create_table("ModuleFunctions",
                            :type => :hash,
                            :key_type => "ShortText") do |table|
          table.short_text("name")
          table.short_text("local_names", :type => :vector)
          table.text("document")
          table.reference("module", "Modules")
          table.reference("version", "Versions")
          table.reference("visibility", "Visibilities")
        end

        schema.create_table("Constants",
                            :type => :hash,
                            :key_type => "ShortText") do |table|
          table.short_text("name")
          table.short_text("local_names", :type => :vector)
          table.text("document")
          table.reference("class", "Classes")
          table.reference("module", "Modules")
          table.reference("version", "Versions")
          table.reference("visibility", "Visibilities")
        end

        schema.create_table("SpecialVariables",
                            :type => :hash,
                            :key_type => "ShortText") do |table|
          table.short_text("name")
          table.short_text("local_names", :type => :vector)
          table.text("document")
          table.reference("version", "Versions")
        end

        schema.change_table("Classes") do |table|
          table.index("SingletonMethods", "_key")
          table.index("InstanceMethods", "_key")
          table.index("Constants", "_key")
        end

        schema.change_table("Modules") do |table|
          table.index("SingletonMethods", "_key")
          table.index("InstanceMethods", "_key")
          table.index("Constants", "_key")
        end

        schema.change_table("Objects") do |table|
          table.index("SingletonMethods", "_key")
        end

        if use_view?
          schema.create_view("Entries") do |view|
            view.add("Classes")
            view.add("Modules")
            view.add("SingletonMethods")
            view.add("InstanceMethods")
            view.add("ModuleFunctions")
            view.add("Constants")
            view.add("SpecialVariables")
          end
        else
          schema.create_table("Types",
                              :type => :hash,
                              :key_type => "ShortText") do |table|
          end

          schema.create_table("Entries",
                              :type => :hash,
                              :key_type => "ShortText") do |table|
            table.short_text("name")
            table.short_text("local_names", :type => :vector)
            table.text("document")
            table.text("signature")
            table.text("description")
            table.reference("type", "Types")
            table.reference("class", "Entries")
            table.reference("module", "Entries")
            table.reference("object", "Entries")
            table.reference("version", "Versions")
            table.reference("visibility", "Visibilities")
          end
        end

        schema.create_table("Specs",
                            :type => :patricia_trie,
                            :key_type => "ShortText") do |table|
        end

        schema.create_table("Terms",
                            :type => :patricia_trie,
                            :key_type => "ShortText",
                            :default_tokenizer => "TokenBigram",
                            :key_normalize => true) do |table|
          table.index("Classes.name")
          table.index("Classes.document")
          table.index("Modules.name")
          table.index("Modules.document")
          table.index("Objects.name")
          table.index("Objects.document")
          table.index("SingletonMethods.name")
          table.index("SingletonMethods.document")
          table.index("InstanceMethods.name")
          table.index("InstanceMethods.document")
          table.index("ModuleFunctions.name")
          table.index("ModuleFunctions.document")
          table.index("Constants.name")
          table.index("Constants.document")
          table.index("SpecialVariables.name")
          table.index("SpecialVariables.document")
          unless use_view?
            table.index("Entries.name")
            table.index("Entries.document")
            table.index("Entries.signature")
            table.index("Entries.description")
          end
        end
      end
    end
  end
end
