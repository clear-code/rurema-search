# Copyright (c) 2010 Kouhei Sutou <kou@clear-code.com>
#
# License: LGPLv3+

module RuremaSearch
  class GroongaIndexer
    def initialize(database, bitclust_database)
      @database = database
      @bitclust_database = bitclust_database
    end

    def index
      @bitclust_database.classes.each do |klass|
        index_class(klass)
      end
      @bitclust_database.docs.each do |doc|
        index_document(doc)
      end
      @bitclust_database.libraries.each do |library|
        index_library(library)
      end
    end

    private
    def version
      @version ||= @bitclust_database.properties["version"]
    end

    def encoding
      @encoding ||= @bitclust_database.properties["encoding"]
    end

    def index_class(klass)
      add_class(klass)
      klass.entries.each do |entry|
        add_entry(klass, entry)
        add_spec(klass, entry)
      end
    end

    def index_document(document)
      source = entry_source(document)
      attributes = {
        :name => document.name,
        :label => document.title,
        :type => "document",
        :document => source,
        :description => "#{document.title} #{source}",
        :version => version,
      }
      @database.entries.add("#{version}:#{document.name}",
                            attributes)
    end

    def index_library(library)
      source = entry_source(library)
      description = []
      [library.requires, library.classes, library.methods,
       library.sublibraries].each do |entries|
        entries.each do |entry|
          description << entry.name
        end
      end
      description << source
      attributes = {
        :name => library.name,
        :label => library.name,
        :type => "library",
        :document => source,
        :description => description.join(" "),
        :version => version,
      }
      @database.entries.add("#{version}:#{library.name}",
                            attributes)
    end

    def add_class(klass)
      source = entry_source(klass)
      @database.entries.add("#{version}:#{klass.name}",
                            :name => klass.name,
                            :label => klass.name,
                            :type => klass.type.to_s,
                            :version => version,
                            :document => source,
                            :description => source)
      @database.specs.add(klass.name, :type => klass.type.to_s)
    end

    def add_entry(klass, entry)
      source = entry_source(entry)
      foreach_method_chunk(source) do |signatures, description|
        signatures.each do |signature|
          attributes = {
            :name => entry.spec_string,
            :label => "#{klass.name}#{entry.typemark}#{signature}",
            :local_names => entry.names,
            :type => normalize_type_label(entry.type_label),
            :version => version,
            :document => source,
            :signature => signature.to_s,
            :description => description,
            :visibility => entry.visibility.to_s
          }
          klass_name = klass.name
          klass_type = normalize_type_label(klass.type.to_s)
          if klass.class?
            attributes[:class] = klass.name
            @database.classes.add(klass.name, :type => klass_type)
          elsif klass.module?
            attributes[:module] = klass.name
            @database.modules.add(klass.name, :type => klass_type)
          else
            attributes[:object] = klass.name
            @database.objects.add(klass.name, :type => klass_type)
          end
          @database.entries.add("#{version}:#{entry.spec_string}:#{signature}",
                                attributes)
        end
      end
    end

    def add_spec(klass, entry)
      @database.specs.add(entry.spec_string,
                          :type => normalize_type_label(entry.type_label))
    end

    def normalize_type_label(label)
      label.gsub(/ /, '-')
    end

    def foreach_method_chunk(source, &block)
      @screen ||= BitClust::TemplateScreen.new(:database => @bitclust_database)
      @screen.send(:foreach_method_chunk, source, &block)
    end

    def entry_source(entry)
      source = entry.source
      if source.respond_to?(:force_encoding)
        source.force_encoding(@bitclust_database.encoding)
      end
      source
    end
  end
end
