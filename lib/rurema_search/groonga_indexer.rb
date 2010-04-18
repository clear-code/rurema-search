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
        case entry.typename
        when :singleton_method
          add_singleton_method(klass, entry)
        when :instance_method
          add_instance_method(klass, entry)
        when :module_function
          add_module_function(klass, entry)
        when :constant
          add_constant(klass, entry)
        when :special_variable
          add_special_variable(entry)
        end
        add_entry(klass, entry)
      end
    end

    def add_class(klass)
      if klass.class?
        @database.classes.add(class_key(klass),
                              :name => klass.name,
                              :version => version,
                              :document => klass.source)
      elsif klass.module?
        @database.modules.add(module_key(klass),
                              :name => klass.name,
                              :version => version,
                              :document => klass.source)
      else
        @database.objects.add(object_key(klass),
                              :name => klass.name,
                              :version => version,
                              :document => klass.source)
      end
      unless @database.use_view?
        @database.entries.add(class_key(klass),
                              :name => klass.name,
                              :type => klass.type.to_s,
                              :version => version,
                              :document => klass.source)
      end
    end

    def add_singleton_method(klass, entry)
      methods = @database.singleton_methods
      methods.add("#{version}:#{entry.spec_string}",
                  :name => entry.spec_string,
                  :version => version,
                  :document => entry.source,
                  :class => class_key(klass),
                  :visibility => entry.visibility.to_s)
    end

    def add_instance_method(klass, entry)
      methods = @database.instance_methods
    end

    def add_method(methods, klass, entry)
      attributes = {
        :name => entry.spec_string,
        :local_names => entry.names,
        :version => version,
        :document => entry.source,
        :visibility => entry.visibility.to_s,
      }
      if klass.class?
        attributes[:class] = class_key(klass)
      elsif klass.module?
        attributes[:module] = module_key(klass)
      else
        attributes[:object] = object_key(klass)
      end
      methods.add("#{version}:#{entry.spec_string}", attributes)
    end

    def add_module_function(klass, entry)
      methods = @database.module_functions
      methods.add("#{version}:#{entry.spec_string}",
                  :name => entry.spec_string,
                  :local_names => entry.names,
                  :version => version,
                  :document => entry.source,
                  :module => module_key(klass),
                  :visibility => entry.visibility.to_s)
    end

    def add_constant(klass, entry)
      @database.constants.add(entry.name,
                              :name => entry.spec_string,
                              :document => entry.source,
                              :class => class_key(klass))
    end

    def add_special_variable(entry)
      @database.special_variables.add(entry.name,
                                      :name => entry.spec_string,
                                      :document => entry.source)
    end

    def add_entry(klass, entry)
      return if @database.use_view?
      attributes = {
        :name => entry.spec_string,
        :local_names => entry.names,
        :type => normalize_type_label(entry.type_label),
        :version => version,
        :document => entry.source,
        :visibility => entry.visibility.to_s
      }
      if klass.class?
        attributes[:class] = class_key(klass)
      elsif klass.module?
        attributes[:module] = module_key(klass)
      else
        attributes[:object] = object_key(klass)
      end
      @database.entries.add("#{version}:#{entry.spec_string}",
                            attributes)
    end

    def normalize_type_label(label)
      label.gsub(/ /, '-')
    end

    def class_key(klass)
      "#{version}:#{klass.name}"
    end

    def module_key(klass)
      "#{version}:#{klass.name}"
    end

    def object_key(klass)
      "#{version}:#{klass.name}"
    end
  end
end
