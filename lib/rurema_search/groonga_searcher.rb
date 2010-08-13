# -*- coding: utf-8 -*-
#
# Copyright (c) 2010 Kouhei Sutou <kou@clear-code.com>
#
# License: LGPLv3+

require 'erb'
require 'net/smtp'
require 'etc'
require 'socket'
require 'nkf'
require 'rack'

module RuremaSearch
  class GroongaSearcher
    module Utils
      module_function
      def production?
        ENV["RACK_ENV"] == "production"
      end

      def passenger?
        ENV["PASSENGER_ENVIRONMENT"] or
          /Phusion_Passenger/ =~ ENV["SERVER_SOFTWARE"].to_s
      end

      def apache?
        /Apache/ =~ ENV["SERVER_SOFTWARE"].to_s
      end

      def thin?
        /\bthin\b/ =~ (ENV["SERVER_SOFTWARE"] || "")
      end

      def open_search_description_base_name
        "open_search_description.xml"
      end

      def open_search_description_path?(path)
        /\/#{Regexp.escape(open_search_description_base_name)}\z/ =~ path
      end
    end

    module PageUtils
      include ERB::Util
      include Utils

      module_function
      def site_title
        "るりまサーチ"
      end

      def site_description
        "Rubyのリファレンスマニュアルを検索"
      end

      def catch_phrase
        "Rubyでgroonga使ってRubyのリファレンスマニュアルを全文検索！"
      end

      def open_search_description_path
        _version = version
        if _version
          full_path("version:#{_version}", open_search_description_base_name)
        else
          full_path(open_search_description_base_name)
        end
      end

      def open_search_description_mime_type
        "application/opensearchdescription+xml"
      end

      def base_path
        script_name = @request.script_name
        script_name += "/" if /\/\z/ !~ script_name
        script_name
      end

      def full_path(*components)
        "#{base_path}#{components.join('/')}"
      end

      def top_path
        full_path
      end

      def image_path(*components)
        full_path("images", *components)
      end

      def base_url
        (URI(@request.url) + base_path).to_s
      end

      def version_url
        url = base_url
        _version = version
        url += "version:#{_version}/" if _version
        url
      end

      def groonga_version
        major, minor, micro, tag = Groonga::VERSION
        [[major, minor, micro].join("."), tag].compact.join("-")
      end

      def h1
        a(tag("img",
              :src => image_path("rurema-search-title.png"),
              :alt => site_title,
              :title => site_title),
          top_path)
      end

      def a(label, href, attributes={})
        tag("a", attributes.merge(:href => href), label)
      end

      def link_version_select(select_version)
        label = h(select_version == :all ? "すべて" : select_version)
        if (version == select_version) or
            (version.nil? and select_version == :all)
          tag("span", {:class => "version-select-text"}, label)
        else
          href = version_select_href(select_version)
          if href.empty?
            href = top_path
          else
            href = full_path(href)
          end
          a(label, href, :class => "version-select-link")
        end
      end

      def version_select_href(version)
        if version == :all
          "../"
        else
          parameter_link_href("version", version)
        end
      end

      def parameter_link_href(key, value)
        "#{key}:#{u(value)}/"
      end

      def link_entry(entry, options={})
        a(options[:label] || entry_label(entry), entry_href(entry))
      end

      def link_entry_if(boolean, entry, options={})
        if boolean
          link_entry(entry, options)
        else
          options[:label] || entry_label(entry)
        end
      end

      def make_breakable(escaped_string)
        escaped_string.gsub(/(::|\.|\.?#|\(\|\)|,|_|\$)/, "<wbr />\\1<wbr />")
      end

      def entry_label(entry)
        make_breakable(h(entry.label))
      end

      def entry_href(entry)
        name = entry.name.key
        mapper = url_mapper(entry.version.key)
        case entry.type.key
        when "class", "module", "object"
          mapper.class_url(name)
        when "constant", "variable", "instance-method", "module-function",
               "singleton-method"
          mapper.method_url(name)
        when "document"
          mapper.document_url(name)
        when "library"
          mapper.library_url(name)
        when "function", "macro"
          mapper.function_url(name)
        else
          "/#{entry.type.key}"
        end
      end

      def drilldown_item(entries, drilldown_column, label_column)
        result = entries.group(drilldown_column)
        result = result.sort([["_nsubrecs", :descending]], :limit => 10)
        result.collect do |record|
          label = record[label_column]
          {
            :label => label,
            :n_records => record.n_sub_records
          }
        end
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
        "function" => "関数",
        "macro" => "マクロ",
      }
      def type_label(type)
        TYPE_LABELS[type] || type
      end

      def link_drilldown_item(key, record)
        if key == "type"
          link_type_raw(record[:label])
        else
          label = record[:label]
          label = library_label(label) if key == "library"
          a(make_breakable(h(label)),
            "./#{parameter_link_href(key, record[:label])}")
        end
      end

      def link_type(entry)
        link_type_raw(entry.type.key)
      end

      def link_type_raw(linked_type)
        a(h(type_label(linked_type)),
          "./#{parameter_link_href('type', linked_type)}")
      end

      PARAMETER_LABELS = {
        "query" => "クエリ",
        "version" => "バージョン",
        "type" => "種類",
        "module" => "モジュール",
        "class" => "クラス",
        "object" => "オブジェクト",
        "instance-method" => "インスタンスメソッド",
        "singleton-method" => "シングルトンメソッド",
        "module-function" => "モジュールファンクション",
        "constant" => "定数",
        "variable" => "変数",
        "library" => "ライブラリ",
        "function" => "関数",
        "macro" => "マクロ",
      }
      def parameter_label(key)
	PARAMETER_LABELS[key] || key
      end

      LIBRARY_LABELS = {"_builtin" => "ビルトイン"}
      def library_label(label)
        LIBRARY_LABELS[label] || label
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

      def analyze
        if production? and respond_to?(:analytics)
          analytics
        else
          ""
        end
      end

      DOCUMENT_OPTIONS_KEY = "rurema-search.document.options"
      def document_options
        @document_options ||= @request.env[DOCUMENT_OPTIONS_KEY] || {}
      end

      def create_url_mapper(version)
        base_url = document_options["base_url"] || base_path
        if document_options["remove_dot_from_version"]
          version = version.gsub(/\./, '')
        end
        RuremaSearch::URLMapper.new(:base_url => base_url,
                                    :version => version)
      end
    end

    include Rack::Utils
    include Utils

    def initialize(database, base_dir, options={})
      @database = database
      @base_dir = base_dir
      @options = options
      setup_view
    end

    def call(env)
      env[PageUtils::DOCUMENT_OPTIONS_KEY] = @options[:document]
      request = Rack::Request.new(normalize_environment(env))
      response = Rack::Response.new
      response["Content-Type"] = "text/html; charset=UTF-8"

      query = request['query'] || ''
      if query.empty?
        dispatch(request, response)
      else
        path_info = request.path_info.gsub(/\/query:.+?\//, '/')
        encoding = request['encoding']
        if encoding
          query.force_encoding(encoding)
          query = query.encode("utf-8")
        end
        request.path_info = "#{path_info}query:#{escape(query)}/"
        response.redirect(request.url.split(/\?/, 2)[0])
      end
      response.to_a
    end

    def error_page(env, exception)
      page = ErrorPage.new(env, exception)
      page.extend(@view)
      page.process
    end

    private
    def dispatch(request, response)
      dispatcher = Dispatcher.new(@database, request, response)
      page = dispatcher.dispatch
      page.extend(@view)
      page.process
    end

    def setup_view
      @view = Module.new
      ["layout",
       "index",
       "search_header", "search", "search_result", "search_no_result",
       "error", "analytics",
       ["open_search_description", "xml"]].each do |template_name, extension|
        template = create_template(template_name, extension)
        next if template.nil?
        @view.send(:define_method, template_name) do
          template.result(binding)
        end
      end
    end

    def create_template(name, extension=nil)
      extension ||= "html"
      template_file = File.join(@base_dir, "views", "#{name}.#{extension}.erb")
      return nil unless File.exist?(template_file)
      erb = ERB.new(File.read(template_file), 0, "%<>")
      erb.filename = template_file
      erb
    end

    def need_normalize_environment?(env)
      passenger? or apache?
    end

    def normalize_environment(env)
      return env unless need_normalize_environment?(env)
      normalized_env = {}
      env.each do |key, value|
        case key
        when "PATH_INFO", "REQUEST_URI"
          value = normalize_path(value)
        end
        normalized_env[key] = value
      end
      normalized_env
    end

    def normalize_path(path)
      return path if open_search_description_path?(path)
      components = path.split(path_split_re)
      components.shift if components.first.empty?
      components.pop if components.last == "/"
      return path if components.empty?
      components.each_slice(2).collect do |key, value|
        "#{key}#{escape(value)}"
      end.join + "/"
    end

    def path_split_re
      @path_split_re ||= /(#{Regexp.union(path_split_keys)}|\/\z)/
    end

    def path_split_keys
      SearchPage::PARAMETER_LABELS.keys.collect do |key|
        "/#{key}:"
      end
    end

    class Dispatcher
      include PageUtils

      def initialize(database, request, response)
        @database = database
        @request = request
        @response = response
      end

      def dispatch
        if open_search_description_path?(@request.path_info)
          OpenSearchDescriptionPage.new(@request, @response)
        else
          case @request.path_info
          when /\A\/(?:version:([^\/]+)\/)?\z/
            version = $1
            IndexPage.new(@database, version, @request, @response)
          else
            SearchPage.new(@database, @request, @response)
          end
        end
      end
    end

    class IndexPage
      include PageUtils

      def initialize(database, version, request, response)
        @database = database
        @version = version || :all
        @request = request
        @response = response
      end

      def process
        entries = @database.entries
        @versions = entries.group("version").sort(["_key"], :limit => -1)
        @version_names = [:all]
        @version_n_entries = [entries.size]
        @versions.each do |version|
          @version_names << version.key.key
          @version_n_entries << version.n_sub_records
        end

        prepare_built_in_classes(entries)
        prepare_drilldown_items(entries)

        @response.write(layout)
      end

      private
      def header
        ""
      end

      def body
        index
      end

      def title
        if version == :all
          "Rubyリファレンスマニュアル全文検索 | #{site_title}"
        else
          "Ruby #{version} | #{site_title}"
        end
      end

      def version
        @version
      end

      def query
        ""
      end

      def prepare_built_in_classes(entries)
        built_in_classes = entries.select do |record|
          conditions = []
          conditions << (record.library == "_builtin")
          conditions << (record.version == version) unless version == :all
          conditions
        end.group("class")

        sort_and_group = Proc.new do |*args, &block|
          built_in_classes.sort(*args).select do |record|
            record.n_sub_records > 25
          end.group_by(&block).sort_by do |(key, classes)|
            representing_value, label = key
            representing_value
          end.collect do |(key, classes)|
            representing_value, label = key
            [label, classes]
          end
        end

        sorted_classes = sort_and_group.call(["_key"]) do |record|
          case record.key.key[0]
          when "A"..."F"
            ["A", "A〜E"]
          when "F"..."K"
            ["F", "F〜J"]
          when "K"..."P"
            ["K", "K〜O"]
          when "P"..."U"
            ["P", "P〜T"]
          else
            ["U", "U〜Z"]
          end
        end
        @built_in_classes_sort_by_name = sorted_classes

        sorted_classes = sort_and_group.call([["_nsubrecs", :descending],
                                              ["_key"]],
                                             :limit => 20) do |record|
          case record.n_sub_records
          when 0...101
            [-100, "〜100件"]
          when 101...201
            [-200, "〜200件"]
          when 201...301
            [-300, "〜300件"]
          else
            [-301, "300件〜"]
          end
        end
        @built_in_classes_sort_by_frequency = sorted_classes
      end

      def prepare_drilldown_items(entries)
        @drilldown_items = drilldown_items(entries)
      end

      def drilldown_items(entries)
        unless version == :all
          entries = entries.select do |record|
            record.version == version
          end
        end

        result = []
        ["type"].each do |column|
          item = drilldown_item(entries, column, "_key")
          result << [column, item] unless item.empty?
        end
        result
      end
    end

    class SearchPage
      include PageUtils

      def initialize(database, request, response)
        @database = database
        @request = request
        @response = response
        @url_mappers = {}
      end

      def process
        start = Time.now.to_f
        _, *parameters = @request.path_info.split(/\//)
        conditions = parse_parameters(parameters)
        entries = @database.entries
        result = entries.select do |record|
          conditions.collect do |condition|
            condition.call(record)
          end.flatten
        end
        @expression = result.expression
        @drilldown_items = drilldown_items(result)
        @entries = result.paginate([["_score", :descending],
                                    ["label", :ascending]],
                                   :page => ensure_page(result.size),
                                   :size => n_entries_per_page)
        @grouped_entries = group_entries(@entries)
        @versions = @database.versions
        @elapsed_time = Time.now.to_f - start
        @response.write(layout)
      end

      private
      def header
        search_header
      end

      def body
        search
      end

      def parse_parameters(parameters)
        @parameters = {}
        @ordered_parameters = []
        @instance_method = nil
        parameters.each do |parameter|
          parameter = parameter.force_encoding("UTF-8")
          key, value = parameter.split(/:/, 2)
          unescaped_value = unescape_value(value)
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

      def unescape_value(value)
        unescaped_value = URI.unescape(value)
        unescaped_value = URI.unescape(unescaped_value) if thin?
        unescaped_value.gsub(/\+/, ' ').strip
      end

      def n_entries_per_page
        @n_entries_per_page ||= compute_n_entries_per_page
      end

      def default_page_size
        100
      end

      def compute_n_entries_per_page
        default_n_entries = default_page_size
        max_n_entries = 100
        n_entries = @request["n_entries"] || default_n_entries
        if n_entries
          begin
            n_entries = Integer(n_entries)
          rescue ArgumentError
            n_entries = default_n_entries
          end
        end
        [10, [n_entries, max_n_entries].min].max
      end

      def query
        @parameters["query"]
      end

      def version
        @parameters["version"]
      end

      def type
        @parameters["type"]
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
                  (match_record["signature"] * 50) |
                  (match_record["summary"] * 25) |
                  (match_record["description"] * 10) |
                  (match_record["document"])
              end
              value.split.collect do |word|
                target =~ word
              end
            end
          when "instance-method", "singleton-method", "module-function",
            "constant"
            conditions << equal_condition("type", key)
            conditions << equal_condition("name._key", value)
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
        if type
          ["class", "module", "object", "library"].each do |column|
            next if @parameters[column]
            item = drilldown_item(entries, column, "_key")
            result << [column, item] unless item.empty?
          end
        else
          item = drilldown_item(entries, "type", "_key")
          result << ["type", item] if item.size > 1
        end
        result
      end

      def group_entries(entries)
        grouped_entries = []
        previous_entry = nil
        entries.each do |entry|
          if previous_entry.nil? or previous_entry.label != entry.label
            grouped_entries << [entry, [entry]]
          else
            grouped_entries.last[1] << entry
          end
          previous_entry = entry
        end
        grouped_entries.collect do |represent_entry, sub_entries|
          [represent_entry, sub_entries.sort_by {|entry| entry.version.key}]
        end
      end

      def ensure_page(n_entries)
        page = @request["page"]
        return 1 if page.nil? or page.empty?

        begin
          page = Integer(page)
        rescue ArgumentError
          return 1
        end
        return 1 if page < 0
        return 1 if (page - 1) * n_entries_per_page > n_entries
        page
      end

      def title
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

      def parameter_value_label(key, value)
        case key
        when "type"
          type_label(value)
        when "library"
          library_label(value)
        else
          value
        end
      end

      def parameter_link_label(key, value)
        "#{parameter_label(key)}:#{parameter_value_label(key, value)}"
      end

      def topic_path
        elements = []
        n_elements = @ordered_parameters.size
        @ordered_parameters.each_with_index do |(key, value), i|
          element = topic_path_element(key, value, i, n_elements)
          remove_href = topic_path_condition_remove_href(i)
          element << a(tag("img",
                           {
                             :alt => "[x]",
                             :title => "条件を削除",
                             :src => image_path("drop-condition-icon.png"),
                           }),
                       remove_href,
                       :class => "drop-condition")
          elements << element
        end
        return "" if elements.empty?

        elements.unshift(tag("span", {:class => "all-items"},
                             a(h("トップページ"), top_path)))
        elements.collect do |element|
          tag("span", {:class => "topic-element"}, element)
        end.join(h(" > "))
      end

      ICON_AVAILABLE_PARAMETERS = ["version", "type", "query", "module",
                                   "library"]
      def topic_path_element(key, value, i, n_elements)
        href = "./" + "../" * (n_elements - i - 1)
        key_label = parameter_label(key)
        if ICON_AVAILABLE_PARAMETERS.include?(key)
          key_label = tag("img",
                          {
                            :class => "parameter-#{key}",
                            :alt => key_label,
                            :title => key_label,
                            :src => image_path("#{key}-icon.png"),
                          })
        else
          key_label = h(key_label)
        end
        value_label = h(parameter_value_label(key, value))
        last_element_p = (i == n_elements - 1)
        unless last_element_p
          value_label = a(value_label, href)
        end
        "#{key_label}:#{value_label}"
      end

      def topic_path_condition_remove_href(i)
        after_parameters = @ordered_parameters[(i + 1)..-1]
        excluded_path = "../" * (after_parameters.size + 1)
        after_parameters.each do |key, value|
          excluded_path << parameter_link_href(key, value)
        end
        excluded_path
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

      def link_version(entry)
        label = h(entry.version.key)
        entry_version = entry.version.key
        if version == entry_version
          label
        else
          a(label, "./version:#{u(entry_version)}/")
        end
      end

      def snippet_width
        300
      end

      def snippet_description(entry)
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
        @parameters.each do |key, value|
          next if key == "query"
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

      def collect_related_entries(entries)
        _related_entries = {}
        entries.each do |entry|
          related_entries(entry, _related_entries)
        end
        _related_entries.values.sort_by do |_entry|
          _entry[:key]
        end
      end

      def related_entries(entry, entries={})
        entries ||= {}
        ["class", "module", "object"].each do |type|
          related_entry = entry[type]
          next if related_entry.nil?
          current_value = @parameters[type]
          next if related_entry.key == current_value
          entries[related_entry.key] = {
            :key => related_entry.key,
            :label => related_entry.key,
            :type => type,
          }
        end
        entry.related_names.each do |name|
          next if name.nil? # "E" is missing. Why?: TODO
          entries[name.key] = {
            :key => name.key,
            :label => name.key,
            :type => "query",
          }
        end
        entries
      end

      def link_related_entry(related_entry)
        key = related_entry[:key]
        label = related_entry[:label]
        type = related_entry[:type]
        if @parameters[type]
          href = "/"
          @ordered_parameters.each do |_key, _value|
            next if _key == type
            href << parameter_link_href(_key, _value)
          end
          href << parameter_link_href(type, key)
          a(label, href)
        else
          a(label, "./#{parameter_link_href(type, key)}")
        end
      end

      def link_type_raw(linked_type)
        if type == linked_type
          h(type_label(linked_type))
        else
          super
        end
      end

      def url_mapper(version)
        @url_mappers[version] ||= create_url_mapper(version)
      end

      def paginate
        return unless @entries.have_pages?
        _paginate = ['']

        if @entries.first_page?
          _paginate << h("<<")
        else
          _paginate << a(h("<<"), paginate_path(@entries.first_page))
          _paginate << a(h("<"), paginate_path(@entries.previous_page))
        end
        paginate_content_middle(_paginate)
        if @entries.last_page?
          _paginate << h(">>")
        else
          _paginate << a(h(">"), paginate_path(@entries.next_page))
          _paginate << a(h(">>"), paginate_path(@entries.last_page))
        end

        _paginate << ""
        _paginate = _paginate.collect do |link|
          case link
          when ""
            link
          when @entries.current_page.to_s
            tag("span", {"class" => "paginate-current"}, link)
          when /\A<a/
            tag("span", {"class" => "paginate-link"}, link)
          else
            tag("span", {"class" => "paginate-text"}, link)
          end
        end
        tag("div", {"class" => "paginate"}, _paginate.join("\n"))
      end

      def paginate_content_middle(_paginate)
        abbreved = false
        @entries.pages.each do |page|
          if page == @entries.current_page
            _paginate << h(page)
          elsif (@entries.current_page - page).abs < 3
            if abbreved
              _paginate << "..."
              abbreved = false
            end
            _paginate << a(h(page), paginate_path(page))
          else
            abbreved = true
          end
        end
        if abbreved
          _paginate << "..."
        end
      end

      def paginate_path(page)
        if page == 1
          path = "./"
          if @entries.page_size != default_page_size
            path << "?n_entries=#{@entries.page_size}"
          end
        else
          path = "?page=#{page}"
          if @entries.page_size != default_page_size
            path << ";n_entries=#{@entries.page_size}"
          end
        end
        path
      end
    end

    class OpenSearchDescriptionPage
      include PageUtils

      def initialize(request, response)
        @request = request
        @response = response
      end

      def process
        @response["Content-Type"] = open_search_description_mime_type
        @response.write(open_search_description)
      end

      private
      def version
        if /\/version:([\d.]+?)\// =~ @request.path_info
          $1
        else
          nil
        end
      end
    end

    class ErrorPage
      include PageUtils

      def initialize(env, exception)
        @env = env
        @exception = exception
        @request = Rack::Request.new(env)
        @response = Rack::Response.new
        @response["Content-Type"] = "text/html; charset=UTF-8"
        @response.status = 500
      end

      def process
        @response.write(layout)
        @response.to_a
      end

      private
      def title
        "エラー | #{site_title}"
      end

      def version
        nil
      end

      def query
        ""
      end

      def header
        "<h1>#{h1}</h1>"
      end

      def body
        error
      end
    end
  end
end
