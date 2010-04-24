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
      ["layout", "search_result", "analytics"].each do |template_name|
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
        @parameters = {}
        @ordered_parameters = []
        @instance_method = nil
        parameters.each do |parameter|
          parameter = parameter.force_encoding("UTF-8")
          key, value = parameter.split(/:/, 2)
          unescaped_value = URI.unescape(value).gsub(/\+/, ' ').strip
          # TODO: raise unless unescaped_value.valid_encoding?
          next unless parse_parameter(key, unescaped_value)
          @ordered_parameters << [key, unescaped_value]
        end
        create_conditions
      end

      def parse_parameter(key, value)
        label = parameter_label(key)
        return false if key == label
        if @parameters.has_key?(key)
          @parameters[key] << " #{value}" if key == "query"
          false
        else
          @parameters[key] = value
          true
        end
      end

      PARAMETER_LABELS = {
        "query" => "クエリ",
        "version" => "バージョン",
        "type" => "種類",
        "module" => "モジュール",
        "class" => "クラス",
        "module" => "モジュール",
        "object" => "オブジェクト",
        "instance-method" => "インスタンスメソッド",
        "singleton-method" => "シングルトンメソッド",
        "module-function" => "モジュールファンクション",
        "constant" => "定数",
        "variable" => "変数",
      }
      def parameter_label(key)
	PARAMETER_LABELS[key] || key
      end

      def query
        @parameters["query"]
      end

      def create_conditions
        conditions = []
        @parameters.each do |key, value|
          case key
          when "query"
            conditions << Proc.new do |record|
              target = record.match_target do |match_record|
                (match_record["local_name"] * 1000) |
                  (match_record["name"] * 100) |
                  (match_record["signature"] * 10) |
                  (match_record["description"])
              end
              target =~ value
            end
          when "instance-method", "singleton-method", "module-function",
            "constant"
            conditions << equal_condition("name", value)
            conditions << equal_condition("type", key)
          else
            conditions << equal_condition(key, value)
          end
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
        if @parameters["type"]
          [["class", "クラス"],
           ["module", "モジュール"],
           ["object", "オブジェクト"]].each do |column, label|
            next if @parameters[column]
            item = drilldown_item(entries, column, "_key")
            result << [column, label, item] unless item.empty?
          end
        else
          item = drilldown_item(entries, "type", "_key")
          result << ["type", "種類", item] if item.size > 1
        end
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
        return 1 if (page - 1) * @n_entries_per_page > @n_entries
        page
      end

      def title
        site_title = "るりまサーチ"
        parameters = []
        @ordered_parameters.each do |key, value|
          parameters << parameter_link_label(key, value)
        end
        if parameters.empty?
          site_title
        else
          "#{parameters.join(' > ')} | #{site_title}"
        end
      end

      def h1
        a(tag("img",
              :src => "/images/rurema-search-title.png",
              :alt => "るりまサーチ",
              :title => "るりまサーチ"),
          "/")
      end

      def parameter_link_label(key, value)
        if key == "type"
          value_label = type_label(value)
        else
          value_label = value
        end
        "#{parameter_label(key)}:#{value_label}"
      end

      def parameter_link_href(key, value)
        "#{key}:#{u(value)}/"
      end

      def topic_path
        elements = []
        n_elements = @ordered_parameters.size
        @ordered_parameters.each_with_index do |(key, value), i|
          href = "./" + "../" * (n_elements - i - 1)
          label = h(parameter_link_label(key, value))
          if i == n_elements - 1
            element = label
          else
            element = a(label, href)
          end
          remove_href = topic_path_condition_remove_href(i)
          element << a("[x]", remove_href)
          elements << element
        end
        return "" if elements.empty?

        elements.unshift(a(h("全件表示"), "/"))
        elements.collect do |element|
          tag("span", {:class => "topic-element"}, element)
        end.join(h(" > "))
      end

      def topic_path_condition_remove_href(i)
        after_parameters = @ordered_parameters[(i + 1)..-1]
        excluded_path = "../" * (after_parameters.size + 1)
        after_parameters.each do |key, value|
          excluded_path << parameter_link_href(key, value)
        end
        excluded_path
      end

      def link_version_select(version)
        href = version_select_href(version)
        if href.empty?
          href = "/"
        else
          href = "/#{href}"
        end
        a(h(version == :all ? "すべて" : version), href)
      end

      def version_select_href(version)
        @no_version_parameters ||= @ordered_parameters.reject do |key, value|
          key == "version"
        end
        parameters = []
        case version
        when :all
          parameters = @no_version_parameters
        else
          parameters = @no_version_parameters + [["version", version]]
        end
        parameters.collect do |key, value|
          parameter_link_href(key, value)
        end.join
      end

      def link_entry(entry)
        label = entry.label || entry.name
        a(h(label).gsub(/(::|\.|\.?#|\(\|\)|,|_|\$)/, "<wbr />\\1<wbr />"),
          entry_href(entry))
      end

      def entry_href(entry)
        mapper = url_mapper(entry.version.key)
        case entry.type.key
        when "class", "module", "object"
          mapper.class_url(entry.name)
        when "constant", "variable", "instance-method", "module-function",
               "singleton-method"
          mapper.method_url(entry.name)
        when "document"
          mapper.document_url(entry.name)
        when "library"
          mapper.library_url(entry.name)
        else
          "/#{entry.type.key}"
        end
      end

      def link_drilldown_item(key, record)
        if key == "type"
          link_type_raw(record[:label])
        else
          a(h(record[:label]), "./#{parameter_link_href(key, record[:label])}")
        end
      end

      def link_type(entry)
        link_type_raw(entry.type.key)
      end

      def link_type_raw(type)
        a(h(type_label(type)), "./#{parameter_link_href('type', type)}")
      end

      TYPE_LABELS = {
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
        TYPE_LABELS[type] || type
      end

      def link_version(entry)
        a(h(entry.version.key), "./version:#{u(entry.version.key)}/")
      end

      def snippet_width
        300
      end

      def format_description(entry)
        @snippet ||= create_snippet
        description = remove_markup(entry.description)
        snippet_description = nil
        if @snippet and description
          snippets = @snippet.execute(description)
          unless snippets.empty?
            separator = tag("span", {:class => "separator"}, "...")
            snippets = snippets.collect do |snippet|
              tag("div", {:class => "snippet"},
                  "#{separator}#{snippet}#{separator}")
            end
            snippet_description = snippets.join("")
          end
        end
        if snippet_description.nil? and description and !description.empty?
          if description.size > snippet_width
            snippet_description = h(description[0, snippet_width] + "...")
          else
            snippet_description = h(description)
          end
        end
        tag("div", {:class => "snippets"}, snippet_description)
      end

      def create_snippet
        open_tag = "<span class=\"keyword\">"
        close_tag = "</span>"
        options = {
          :normalize => true,
          :width => snippet_width,
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
        last_page = @n_entries / @n_entries_per_page + 1
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
        if production? and respond_to?(:analytics)
          analytics
        else
          ""
        end
      end
    end
  end
end
