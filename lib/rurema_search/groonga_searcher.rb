# -*- coding: utf-8 -*-
#
# Copyright (c) 2010 Kouhei Sutou <kou@clear-code.com>
#
# License: LGPLv3+

require 'erb'
require 'rack'

module RuremaSearch
  class GroongaSearcher
    include Rack::Utils

    def initialize(database, base_dir)
      @database = database
      @base_dir = base_dir
      setup_view
    end

    def call(env)
      request = Rack::Request.new(env)
      response = Rack::Response.new
      response["Content-Type"] = "text/html; charset=UTF-8"

      if request.post?
        query = request['query'] || ''
        unless query.empty?
          path_info = request.path_info.gsub(/\/query:.+?\//, '/')
          request.path_info = "#{path_info}query:#{escape(query)}/"
        end
        response.redirect(request.url.split(/\?/, 2)[0])
      else
        context = SearchContext.new(@database, request, response)
        context.extend(@view)
        context.process
      end
      response.to_a
    end

    private
    def setup_view
      @view = Module.new
      ["layout", "search_result", "analystics"].each do |template_name|
        template = create_template(template_name)
        next if template.nil?
        @view.send(:define_method, template_name) do
          template.result(binding)
        end
      end
    end

    def create_template(name)
      template_file = File.join(@base_dir, "views", "#{name}.html.erb")
      return nil unless File.exist?(template_file)
      erb = ERB.new(File.read(template_file), 0, "%<>")
      erb.filename = template_file
      erb
    end

    class SearchContext
      include ERB::Util

      def initialize(database, request, response)
        @database = database
        @request = request
        @response = response
        @url_mappers = {}
        @n_entries_per_page = 100
      end

      def process
        start = Time.now.to_i
        _, *parameters = @request.path_info.split(/\//)
	conditions = parse_parameters(parameters)
        entries = @database.entries
        if conditions.empty?
          @n_entries = entries.size
          @drilldown_items = drilldown_items(entries)
          result = entries.select
          @expression = result.expression
          result = result.select("_score = rand()", :syntax => :script)
        else
          result = entries.select do |record|
            conditions.inject(nil) do |expression, condition|
              if expression
                expression & condition.call(record)
              else
                condition.call(record)
              end
            end
          end
          @expression = result.expression
          @n_entries = result.size
          @drilldown_items = drilldown_items(result)
        end
        @page = ensure_page
        @entries = result.sort([["_score", :descending]],
                               :offset => @n_entries_per_page * (@page - 1),
                               :limit => @n_entries_per_page)
        @versions = @database.versions
        @elapsed_time = Time.now.to_f - start.to_f
        @response.write(layout)
      end

      private
      def parse_parameters(parameters)
        @available_paths = []
        @query = @version = @type = @module = @class = @object = nil
        @instance_method = nil
        parameters.each do |parameter|
          parameter = parameter.force_encoding("UTF-8")
          key, value = parameter.split(/:/, 2)
          unescaped_value = URI.unescape(value).gsub(/\+/, ' ').strip
          # TODO: raise unless unescaped_value.valid_encoding?
          case key
          when "query"
            if @query.nil?
              @query = unescaped_value
            else
              @query << " #{unescaped_value}"
              @available_paths.assoc(key)[1] = unescaped_value
              next
            end
          when "version"
            @version = unescaped_value
          when "type"
            @type = unescaped_value
          when "module"
            @module = unescaped_value
          when "class"
            @class = unescaped_value
          when "object"
            @object = unescaped_value
          when "instance-method"
            @instance_method = unescaped_value
          else
            next
          end
          next if @available_paths.assoc(key)
          @available_paths << [key, unescaped_value]
        end
        create_conditions
      end

      def create_conditions
        conditions = []
        if @query
          conditions << Proc.new do |record|
            target = (record["name"] |
                      record["signature"] |
                      record["description"])
            target.match(@query, :allow_update => false)
          end
        end
        {
          "version" => @version,
          "type" => @type,
          "module" => @module,
          "class" => @class,
          "name" => @instance_method,
        }.each do |column, value|
          conditions << equal_condition(column, value) if value
        end
        conditions
      end

      def equal_condition(column, value)
        Proc.new do |record|
          record[column] == value
        end
      end

      def drilldown_items(entries)
        result = []
        item = drilldown_item(entries, "type", "_key")
        result << [:type, "種類", item] if item.size > 1
        result
      end

      def drilldown_item(entries, drilldown_column, label_column)
        result = entries.group(drilldown_column)
        result = result.sort([["_nsubrecs", :descending]], :limit => 10)
        result.collect do |record|
          {
            :label => record[label_column],
            :n_records => record.n_sub_records
          }
        end
      end

      def ensure_page
        page = @request["page"]
        return 1 if page.nil? or page.empty?

        begin
          page = Integer(page)
        rescue ArgumentError
          return 1
        end
        return 1 if page < 0
        return 1 if page * @n_entries_per_page > @n_entries
        page
      end

      def title
        "Rubyリファレンスマニュアル"
      end

      def h1
        a(tag("img",
              :src => "/images/rurema-search-title.png",
              :alt => "るりまサーチ",
              :title => "るりまサーチ"),
          "/")
      end

      def topic_path
        elements = []
        n_elements = @available_paths.size
        @available_paths.each_with_index do |(key, value), i|
          href = "./" + "../" * (n_elements - i - 1)
          label = h("#{key}:#{value}")
          if i == n_elements - 1
            elements << label
          else
            elements << a(label, href)
          end
        end
        return "" if elements.empty?

        elements.unshift(a(h("全件表示"), "/"))
        elements.collect do |element|
          tag("span", {:class => "topic-element"}, element)
        end.join(h(" > "))
      end

      def link_version_select(version)
        href = version_select_href(version)
        if href.empty?
          href = "/"
        else
          href = "/#{href}/"
        end
        a(h(version == :all ? "すべて" : version), href)
      end

      def version_select_href(version)
        @no_version_paths ||= @available_paths.reject do |key, value|
          key == "version"
        end
        paths = []
        case version
        when :all
          paths = @no_version_paths
        else
          paths = @no_version_paths + [["version", version]]
        end
        paths.collect do |key, value|
          "#{key}:#{u(value)}"
        end.join("/")
      end

      def link_entry(entry)
        label = entry.label || entry.name
        a(h(label).gsub(/(::|\.|\.?#|\(\|\)|,|_|\$)/, "<wbr />\\1<wbr />"),
          entry_href(entry))
      end

      def entry_href(entry)
        mapper = url_mapper(entry.version.key)
        case entry.type.key
        when "class"
          mapper.class_url(entry.name)
        when "constant", "variable", "instance-method", "singleton-method"
          mapper.method_url(entry.name)
        when "document"
          mapper.document_url(entry.name)
        when "library"
          mapper.library_url(entry.name)
        else
          "/#{entry.type.key}"
        end
      end

      def link_type(entry)
        link_type_raw(entry.type.key)
      end

      def link_type_raw(type)
        a(h(type_label(type)), "./type:#{u(type)}/")
      end

      TYPE_LABEL = {
        "class" => "クラス",
        "module" => "モジュール",
        "object" => "オブジェクト",
        "instance-method" => "インスタンスメソッド",
        "singleton-method" => "シングルトンメソッド",
        "module-function" => "モジュールファンクション",
        "constant" => "定数",
        "variable" => "変数",
        "document" => "文書",
        "library" => "ライブラリ",
      }
      def type_label(type)
        TYPE_LABEL[type] || type
      end

      def link_version(entry)
        a(h(entry.version.key), "./version:#{u(entry.version.key)}/")
      end

      def format_description(entry)
        @snippet ||= create_snippet
        description = remove_markup(entry.description)
        snippet_description = nil
        if @snippet and description
          snippets = @snippet.execute(description)
          unless snippets.empty?
            separator = tag("span", {:class => "separator"}, "...")
            snippets << ""
            snippets.unshift("")
            snippet_description = snippets.join(separator)
          end
        end
        if snippet_description.nil? and description and !description.empty?
          if description.size > 140
            snippet_description = h(description[0, 140] + "...")
          else
            snippet_description = h(description)
          end
        end
        tag("div", {:class => "snippet"}, snippet_description)
      end

      def create_snippet
        open_tag = "<span class=\"keyword\">"
        close_tag = "</span>"
        options = {
          :normalize => true,
          :width => 140,
          :html_escape => true,
        }
        snippet = @expression.snippet([open_tag, close_tag], options)
        snippet ||= Groonga::Snippet.new(options)
        [@version, @class, @module, @object, @instance_method].each do |value|
          next if value.nil?
          snippet.add_keyword(value,
                              :open_tag => open_tag,
                              :close_tag => close_tag)
        end
        snippet
      end

      def remove_markup(source)
        return nil if source.nil?
        source.gsub(/\[\[.+?:(.+?)\]\]/, '\1')
      end

      def related_entries(entry)
        entries = []
        add_related_entry(entries, entry["class"], @class)
        add_related_entry(entries, entry["module"], @module)
        add_related_entry(entries, entry["object"], @object)
        description = entry.description
        if description
          @database.specs.scan(description) do |record, word, start, length|
            entries << record
          end
        end
        uniq_entries = {}
        entries.each do |entry|
          uniq_entries[entry.key] = entry
        end
        uniq_entries.values.sort_by do |entry|
          entry.key
        end
      end

      def add_related_entry(entries, related_entry, current_value)
        return if related_entry.nil?
        return if related_entry.key == current_value
        entries << related_entry
      end

      def link_related_entry(related_entry)
        if related_entry.have_column?("label")
          key = related_entry.name
          label = related_entry.label
        else
          key = related_entry.key
          label = related_entry.key
        end
        a(label, "./#{related_entry.type.key}:#{u(key)}/")
      end

      def a(label, href, attributes={})
        tag("a", attributes.merge(:href => href), label)
      end

      def tag(name, attributes={}, content=nil)
        _tag = "<#{name}"
        attributes.each do |key, value|
          _tag << " #{h(key)}=\"#{h(value)}\""
        end
        if content
          _tag << ">#{content}</#{name}>"
        else
          if no_content_tag_name?(name)
            _tag << " />"
          else
            _tag << "></#{name}>"
          end
        end
        _tag
      end

      NO_CONTENT_TAG_NAMES = ["meta", "img"]
      def no_content_tag_name?(name)
        NO_CONTENT_TAG_NAMES.include?(name)
      end

      def url_mapper(version)
        @url_mappers[version] ||= create_url_mapper(version)
      end

      def create_url_mapper(version)
        RuremaSearch::URLMapper.new(:base_url => "/",
                                    :version => version)
      end

      def paginate
        return if @entries.size >= @n_entries
        _paginate = ['']

        if @page == 1
          _paginate << h("<<")
        else
          _paginate << a(h("<<"), "./")
          _paginate << a(h("<"), "?page=#{@page - 1}")
        end
        last_page = @n_entries / @n_entries_per_page
        paginate_content_middle(_paginate, last_page)
        if @page == last_page
          _paginate << h(">>")
        else
          _paginate << a(h(">"), "?page=#{@page + 1}")
          _paginate << a(h(">>"), "?page=#{last_page}")
        end

        _paginate << ""
        _paginate = _paginate.collect do |link|
          case link
          when ""
            link
          when @page.to_s
            tag("span", {"class" => "paginate-current"}, link)
          when /\A<a/
            tag("span", {"class" => "paginate-link"}, link)
          else
            tag("span", {"class" => "paginate-text"}, link)
          end
        end
        tag("div", {"class" => "paginate"}, _paginate.join("\n"))
      end

      def paginate_content_middle(_paginate, last_page)
        abbreved = false
        last_page.times do |page|
          page += 1
          if page == @page
            _paginate << h(page)
          elsif (@page - page).abs < 3
            if abbreved
              _paginate << "..."
              abbreved = false
            end
            _paginate << a(h(page), "?page=#{page}")
          else
            abbreved = true
          end
        end
        if abbreved
          _paginate << "..."
        end
      end

      def production?
        ENV["RACK_ENV"] == "production"
      end

      def analyze
        if production? and respond_to?(:analystics)
          analystics
        else
          ""
        end
      end
    end
  end
end
