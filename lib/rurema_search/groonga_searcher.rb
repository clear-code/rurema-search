# -*- coding: utf-8 -*-
#
# Copyright (c) 2010-2013 Kouhei Sutou <kou@clear-code.com>
#
# License: LGPLv3+

require "erb"
require "etc"
require "socket"
require "nkf"
require "shellwords"
require "rack"

module RuremaSearch
  class GroongaSearcher
    class Error < StandardError
    end

    class ClientError < Error
      attr_reader :status
      def initialize(status, message)
        @status = status
        super(message)
      end
    end

    module Utils
      module_function
      def production?
        ENV["RACK_ENV"] == "production"
      end

      def passenger?(environment=nil)
        environment ||= ENV
        environment["PASSENGER_CONNECT_PASSWORD"] or
          environment["PASSENGER_ENVIRONMENT"] or
          /Phusion_Passenger/ =~ environment["SERVER_SOFTWARE"].to_s
      end

      def apache?(environment=nil)
        environment ||= ENV
        /Apache/ =~ environment["SERVER_SOFTWARE"].to_s
      end

      def thin?(environment=nil)
        environment ||= ENV
        /\bthin\b/ =~ environment["SERVER_SOFTWARE"].to_s
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
      def site_title(version_name=nil)
        version_name ||= version || :all
        if version_name == :all
          "るりまサーチ"
        else
          "るりまサーチ (Ruby #{version_name})"
        end
      end

      def site_description
        "Rubyのリファレンスマニュアルを検索"
      end

      def catch_phrase
        "最速Rubyリファレンスマニュアル検索！"
      end

      def open_search_description_path(version_name=nil)
        version_name ||= version || :all
        if version_name == :all
          full_path(open_search_description_base_name)
        else
          full_path("version:#{version_name}", open_search_description_base_name)
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

      def full_url(*components)
        "#{base_url}#{components.join('/')}"
      end

      def top_path
        full_path
      end

      def auto_complete_api_path
        full_path("api:internal", "auto-complete") + "/"
      end

      IMAGES_DIRECTORY = "images"
      def image_path(*components)
        full_path(IMAGES_DIRECTORY, *components)
      end

      def image_url(*components)
        full_url(IMAGES_DIRECTORY, *components)
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

      def link_version_select(select_version, options={})
        label = h(select_version == :all ? "すべて" : select_version)
        label << options[:label_suffix] if options[:label_suffix]
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
        escaped_string.gsub(/(::|\.|\.?#|\(\|\)|,|_|\/|\$)/, "<wbr />\\1<wbr />")
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

      def entry_url(entry)
        full_url(entry_href(entry).sub(/\A\//, ''))
      end

      def drilldown_item(entries, drilldown_column, label_column,
                         options={})
        sort_key = options[:sort_key] || [["_nsubrecs", :descending]]

        entries = entries.group(drilldown_column)
        entries = entries.sort(sort_key)
        entries.collect do |entry|
          label = entry[label_column]
          {
            :label => label,
            :n_records => entry.n_sub_records
          }
        end
      end

      TYPE_LABELS = {
        "function" => "関数",
        "macro" => "マクロ",
        "document" => "文書",
        "constant" => "定数",
        "variable" => "変数",
      }
      def type_label(type)
        TYPE_LABELS[type] || PARAMETER_LABELS[type] || type
      end

      def link_drilldown_entry(key, entry)
        if key == "type"
          link_type_raw(entry[:label])
        else
          label = entry[:label]
          if label.is_a?(Array)
            href = label.collect do |parameter_value|
              parameter_link_href(key, parameter_value)
            end.join("")
            label = label.join(" ")
          else
            href = parameter_link_href(key, label)
          end
          label = library_label(label) if key == "library"
          a(make_breakable(h(label)), "./#{href}")
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
        "class" => "クラス",
        "module" => "モジュール",
        "object" => "オブジェクト",
        "instance-method" => "インスタンスメソッド",
        "singleton-method" => "特異メソッド",
        "module-function" => "モジュール関数",
        "library" => "ライブラリ",
      }
      def parameter_label(key)
        PARAMETER_LABELS[key] || TYPE_LABELS[key] || key
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

      def default_query_form_value
        current_query = query
        if current_query.is_a?(Array)
          current_query = current_query.collect do |word|
            if /[ "]/ =~ word
              escaped_word = word.gsub(/"/, "\\\"")
              word = "\"#{escaped_word}\""
            end
            word
          end.join(" ")
        end
        h(current_query)
      end
    end

    include Rack::Utils
    include Utils

    def initialize(database, suggest_database, base_dir, options={})
      @database = database
      @suggest_database = suggest_database
      @base_dir = base_dir
      @options = options
      setup_view
    end

    def call(env)
      env[PageUtils::DOCUMENT_OPTIONS_KEY] = @options[:document]
      env["RAW_PATH_INFO"] = env["PATH_INFO"]
      env["RAW_REQUEST_URI"] = env["REQUEST_URI"]
      request = Rack::Request.new(normalize_environment(env))
      response = Rack::Response.new
      response["Content-Type"] = "text/html; charset=UTF-8"
      # response["Connection"] = "close"

      query = request['query']
      query ||= referrer_query(request) unless /\/query:/ =~ request.path_info
      query ||= ''
      if query.empty?
        dispatch(request, response)
      else
        path_info = request.path_info.gsub(/\/query:[^\/]+/, '')
        encoding = request['encoding']
        if encoding
          query.force_encoding(encoding)
          query = query.encode("utf-8")
        end
        words = split_query(query)
        words.each do |word|
          path_info << "query:#{escape(word)}/"
        end
        request.path_info = path_info
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
      dispatcher = Dispatcher.new(@database, @suggest_database,
                                  request, response)
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
      (SearchPage::PARAMETER_LABELS.keys + ["api"]).collect do |key|
        "/#{key}:"
      end
    end

    def split_query(query)
      Shellwords.split(query)
    end

    def referrer_query(request)
      referrer = request.referrer
      return nil if referrer.nil?
      referrer_query = URI(referrer).query
      referrer_parameters = Rack::Utils.parse_nested_query(referrer_query)
      referrer_parameters["q"]
    end

    class Dispatcher
      include PageUtils

      def initialize(database, suggest_database, request, response)
        @database = database
        @suggest_database = suggest_database
        @request = request
        @response = response
      end

      def dispatch
        raw_path = @request.script_name + @request.env["RAW_PATH_INFO"]
        if open_search_description_path?(@request.path_info)
          OpenSearchDescriptionPage.new(@request, @response)
        elsif raw_path == auto_complete_api_path
          API::Internal::AutoComplete.new(@database, @suggest_database,
                                          @request, @response)
        else
          case @request.path_info
          when /\A\/(?:version:([^\/]+)\/)?\z/
            version = $1
            IndexPage.new(@database, version, @request, @response)
          else
            SearchPage.new(@database, @suggest_database, @request, @response)
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
          @version_names << version["_key"]
          @version_n_entries << version.n_sub_records
        end

        prepare_built_in_objects(entries)

        @response.write(layout)

        close_temporary_tables
      end

      private
      def close_temporary_tables
        if @versions and @versions.temporary?
          @versions.close
        end
      end

      def header
        ""
      end

      def body
        index
      end

      def title
        if version == :all
          "#{catch_phrase} | #{site_title}"
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

      def sorted_built_in_objects_by_name(entries, type)
        built_in_objects = entries.select do |record|
          conditions = []
          conditions << (record.library == "_builtin")
          conditions << (record.version =~ version) unless version == :all
          conditions
        end.group(type)

        sort_and_group = Proc.new do |*args, &block|
          grouped_objects = built_in_objects.sort(*args).group_by(&block)
          grouped_objects.sort_by do |(key, objects)|
            representing_value, label = key
            representing_value
          end.collect do |(key, objects)|
            representing_value, label = key
            [label, objects]
          end
        end

        sort_and_group.call(["_key"]) do |record|
          case record["_key"][0]
          when "A"..."F"
            ["A", "A〜E"]
          when "F"..."K"
            ["F", "F〜J"]
          when "K"..."P"
            ["K", "K〜O"]
          when "P"..."T"
            ["P", "P〜S"]
          else
            ["T", "T〜Z"]
          end
        end
      end

      def prepare_built_in_objects(entries)
        sorted_classes = sorted_built_in_objects_by_name(entries, "class")
        sorted_modules = sorted_built_in_objects_by_name(entries, "module")
        @built_in_object_drilldown_items =
          [
           {
             :label => "組み込みクラス一覧",
             :type => "class",
             :objects => sorted_classes,
           },
           {
             :label => "組み込みモジュール一覧",
             :type => "module",
             :objects => sorted_modules,
           },
          ]
      end
    end

    class SearchPage
      # FIXME
      module JSONWriter
        def write_json
          @response["Content-Type"] = "application/json; charset=UTF-8"
          @response.write(JSON.generate(api_result))
        end

        def api_path
          "api:v1"
        end

        def api_result
          {
            :versions => api_result_versions,
            :statistics => api_result_statistics,
            :conditions => api_result_conditions,
            :corrections => api_result_corrections,
            :suggestions => api_result_suggestions,
            :entries => api_result_entries,
          }
        end

        def api_result_versions
          current_version = version || :all
          @version_names.collect do |version_name|
            {
              :name => version_name,
              :selected => current_version == version_name,
            }
          end
        end

        def api_result_statistics
          {
            :total => @entries.n_records,
            :start_offset => @entries.start_offset,
            :end_offset => @entries.end_offset,
            :elapsed_time => @elapsed_time,
          }
        end

        def api_result_conditions
          @ordered_parameters.collect do |(key, value)|
            condition_info = {
              :name => key,
              :value => value,
            }
            if ICON_AVAILABLE_PARAMETERS.include?(key)
              condition_info[:icon_url] = image_url("#{key}-icon.png")
            end
            condition_info
          end
        end

        def api_result_corrections
          @corrections.collect do |item|
            {
              :value => item[:key].join(" "),
              :score => item[:score],
            }
          end
        end

        def api_result_suggestions
          @suggestions.collect do |item|
            {
              :value => item[:key].join(" "),
              :score => item[:score],
            }
          end
        end

        def api_result_entries
          @grouped_entries.collect do |represent_entry, entries|
            {
              :signature => represent_entry.label,
              :score => represent_entry.score,
              :metadata => {
                :type => represent_entry.type.key,
                :versions => entries.collect {|entry| entry.version.key},
              },
              :summary => api_result_clean_text(represent_entry.summary),
              :documents => entries.collect do |entry|
                api_result_entry(entry)
              end,
              :related_entries => api_result_related_entries(entries),
            }
          end
        end

        def api_result_entry(entry)
          description = api_result_clean_text(entry.description)
          snippets = nil
          if description
            @snippet ||= create_snippet
            snippets = @snippet.execute(description) if @snippet
          end
          {
            :version => entry.version.key,
            :url => entry_url(entry),
            :description => description,
            :snippets => snippets || [],
          }
        end

        def api_result_related_entries(entries)
          collect_related_entries(entries).collect do |related_entry|
            info = related_entry_link_info(related_entry)
            {
              :key => info[:key],
              :label => info[:label],
              :type => info[:type],
              :url => full_url(api_path, *info[:parameter_hrefs]),
            }
          end
        end

        def api_result_clean_text(text)
          return nil if text.nil?
          cleaned_text = remove_markup(text).strip
          return nil if cleaned_text.empty?
          cleaned_text
        end
      end

      include PageUtils
      include JSONWriter # FIXME

      def initialize(database, suggest_database, request, response)
        @database = database
        @suggest_database = suggest_database
        @request = request
        @response = response
        @url_mappers = {}
      end

      def process
        process_query
        @response.status = 404 if @entries.empty?
        case @request.path_info
        when /\A\/#{Regexp.escape(api_path)}\//
          write_json
        else
          write_html
        end
        close_temporary_tables
      end

      private
      def process_query
        start = Time.now.to_f
        _, *parameters = @request.path_info.split(/\//)
        parse_parameters(parameters)
        entries = @database.entries
        @result_without_version_condition = entries.select do |record|
          create_conditions_without_version.collect do |condition|
            condition.call(record)
          end.flatten
        end
        if @version_condition
          @result = @result_without_version_condition.select do |record|
            @version_condition.call(record)
          end
          @result.each do |record|
            record.score += record.key.score
          end
        else
          @result = @result_without_version_condition
        end
        @expression = @result.expression
        @drilldown_items = drilldown_items(@result)
        @entries = @result.paginate([["_score", :descending],
                                     ["label", :ascending]],
                                    :page => ensure_page(@result.size),
                                    :size => n_entries_per_page)
        @grouped_entries = group_entries(@entries)
        @leading_grouped_entries = @grouped_entries[0, 5]
        @versions = @result_without_version_condition.group("version")
        @versions = @versions.sort(["_key"], :limit => -1)
        @version_names = [:all]
        @version_n_entries = [@result_without_version_condition.size]
        @versions.each do |version|
          @version_names << version["_key"]
          @version_n_entries << version.n_sub_records
        end
        prepare_corrections
        prepare_suggestions
        @elapsed_time = Time.now.to_f - start
      end

      def close_temporary_tables
        if @result and @result.temporary?
          @result.close
        end
        if @result_without_version_condition and
            @result_without_version_condition.temporary?
          @result_without_version_condition.close
        end
      end

      def write_html
        @response.write(layout)
      end

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
          if value.nil?
            message = "キー<#{key.inspect}>の値がありません。"
            raise ClientError.new(400, message)
          end
          unescaped_value = unescape_value(value)
          # TODO: raise unless unescaped_value.valid_encoding?
          next unless parse_parameter(key, unescaped_value)
          @ordered_parameters << [key, unescaped_value]
        end
      end

      def parse_parameter(key, value)
        label = parameter_label(key)
        return false if key == label
        value.force_encoding("UTF-8") if key == "query"
        if @parameters.has_key?(key)
          if key == "query"
            @parameters[key] << value
            true
          else
            false
          end
        else
          value = [value] if key == "query"
          @parameters[key] = value
          true
        end
      end

      def unescape_value(value)
        unescaped_value = Rack::Utils.unescape(value)
        if thin?(@request.env) or passenger?(@request.env)
          unescaped_value = Rack::Utils.unescape(unescaped_value)
        end
        unescaped_value.strip
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

      def have_scope_parameter?
        @parameters["class"] or
          @parameters["module"] or
          @parameters["object"] or
          @parameters["library"]
      end

      def create_conditions_without_version
        conditions = []
        @version_condition = nil
        @parameters.each do |key, value|
          case key
          when "query"
            conditions << query_condition(key, value)
          when "instance-method", "singleton-method", "module-function",
            "constant"
            conditions << equal_condition("type", key)
            conditions << equal_condition("name._key", value)
          when "version"
            # don't register version condition.
            @version_condition = Proc.new do |record|
              record.version == value
            end
          when "library"
            conditions << Proc.new do |record|
              (record[key].prefix_search(value)) |
                (record[key] == value)
            end
          else
            conditions << equal_condition(key, value)
          end
        end
        conditions
      end

      def query_condition(key, words)
        Proc.new do |record|
          target = record.match_target do |match_record|
            (match_record["name"] * 20000) |
              (match_record["local_name"] * 12000) |
              (match_record["class"] * 12000) |
              (match_record["module"] * 12000) |
              (match_record["object"] * 12000) |
              (match_record["library"] * 8000) |
              (match_record["normalized_class"] * 6000) |
              (match_record["normalized_module"] * 6000) |
              (match_record["normalized_object"] * 6000) |
              (match_record["local_name_raw"] * 3000) |
              (match_record["name_raw"] * 3000) |
              (match_record["signature"] * 100) |
              (match_record["summary"] * 10) |
              (match_record["description"] * 5) |
              (match_record["document"])
          end
          conditions = words.collect do |word|
            target =~ word
          end.inject do |match_conditions, match_condition|
            match_conditions & match_condition
          end

          words.each do |word|
            case word
            when /\A([A-Z][A-Za-z\d]*(?:::[A-Z][A-Za-z\d]*)*)
                  (?:\#|\.|.\#)
                  ([A-Za-z][A-Za-z\d]*[!?=]?)\z/x
              constant = $1
              method_name = $2
              conditions |= ((target =~ constant) & (target =~ method_name))
            end
          end
          conditions
        end
      end

      def equal_condition(column, value)
        Proc.new do |record|
          record[column] == value
        end
      end

      def drilldown_items(entries)
        items = []

        unless type
          drilldown_entries = drilldown_item(entries, "type", "_key")
          if drilldown_entries.size > 1
            items << {:key => "type", :entries => drilldown_entries}
          end
        end

        ["library", "class", "module", "object"].each do |column|
          next if @parameters[column]
          drilldown_entries =
            drilldown_item(entries, column, "_key",
                           :sort_key => [["_key", :ascending]])
          unless drilldown_entries.empty?
            items << {:key => column, :entries => drilldown_entries}
          end
        end

        drilldown_entries = drilldown_item(entries, "local_name", "_key",
                                           :sort_key => [["_key", :ascending]])
        if query and !query.empty?
          drilldown_entries = drilldown_entries.reject do |entry|
            query.include?(entry[:label])
          end
        end
        if drilldown_entries.size > 1
          items << {
            :key => "query",
            :label => "キーワード",
            :entries => drilldown_entries
          }
        end

        items
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

      def grouped_entries_description_snippets(entries)
        snippets = []
        entries.each do |entry|
          snippets.concat(entry_description_snippets(entry))
        end
        snippets.uniq
      end

      def snippet_width
        300
      end

      def entry_description_snippets(entry)
        @snippet ||= create_snippet
        description = remove_markup(entry.description)
        snippets = []
        if @snippet and description
          snippets.concat(@snippet.execute(description))
          separator = tag("span", {:class => "separator"}, "...")
          snippets = snippets.collect do |snippet|
            "#{separator}#{snippet.strip}#{separator}"
          end
        end
        if snippets.empty?
          description ||= ""
          if description.size > snippet_width
            description_snippet = description[0, snippet_width] << "..."
          else
            description_snippet = description
          end
          description_snippet = description_snippet.strip
          snippets << h(description_snippet) unless description_snippet.empty?
        end
        snippets.collect do |snippet|
          tag("div", {:class => "snippet"}, snippet.gsub(/\n/, "<br />"))
        end
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

      def related_entry_link_info(related_entry)
        key = related_entry[:key]
        label = related_entry[:label]
        type = related_entry[:type]

        parameter_values = key
        unless parameter_values.is_a?(Array)
          parameter_values = [parameter_values]
        end
        label ||= parameter_values.join(" ")
        parameter_hrefs = parameter_values.collect do |parameter_value|
          parameter_link_href(type, parameter_value)
        end

        if @parameters[type]
          base_href = "/"
          @ordered_parameters.each do |_key, _value|
            next if _key == type
            base_href << parameter_link_href(_key, _value)
          end
        else
          base_href = "./"
        end
        {
          :key => key,
          :label => label,
          :type => type,
          :base_href => base_href,
          :parameter_hrefs => parameter_hrefs,
        }
      end

      def link_related_entry(related_entry)
        info = related_entry_link_info(related_entry)
        a(info[:label], "#{info[:base_href]}#{info[:parameter_hrefs].join('')}")
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

      def prepare_corrections
        @corrections = []
        return if query.nil? or query.empty?

        word = query.join(" ")
        corrections = @suggest_database.corrections(word, :limit => 5)
        corrections.each do |correction|
          correction_word = correction[:key]
          next if correction_word == word
          correction[:key] = correction_word.split
          @corrections << correction
        end
      end

      def prepare_suggestions
        @suggestions = []
        return if query.nil? or query.empty?

        word = query.join(" ")
        suggestions = @suggest_database.suggestions(word, :limit => 5)
        suggestions.each do |suggestion|
          suggestion_words = suggestion[:key].split - query
          next if suggestion_words.empty?
          suggestion[:key] = suggestion_words
          @suggestions << suggestion
        end
      end
    end

    module API
      module Internal
        class AutoComplete
          def initialize(database, suggest_database, request, response)
            @database = database
            @suggest_database = suggest_database
            @request = request
            @response = response
          end

          def process
            term = (@request["term"] || "").lstrip
            completions = @suggest_database.completions(term)
            if completions.empty? and / / !~ term
              corrections = @suggest_database.corrections(term)
              candidates = corrections
            else
              candidates = completions
            end
            candidates = candidates.collect do |candidate|
              candidate[:key]
            end
            @response["Content-Type"] = "application/json; charset=UTF-8"
            @response.write(JSON.generate(candidates))
          end
        end
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
        @response.status = http_status
      end

      def process
        @version_names = [:all]
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

      def client_error?
        @exception.is_a?(ClientError)
      end

      def http_status
        if client_error?
          @exception.status
        else
          500
        end
      end
    end
  end
end
