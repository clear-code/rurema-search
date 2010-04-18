# -*- coding: utf-8 -*-
# Copyright (c) 2010 Kouhei Sutou <kou@clear-code.com>
#
# License: LGPLv3+

require 'erb'

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
        if query.empty?
          request.path_info = "/"
        else
          request.path_info = "/query:#{escape(query)}/"
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
      ["layout", "search_result"].each do |template_name|
        template = create_template(template_name)
        @view.send(:define_method, template_name) do
          template.result(binding)
        end
      end
    end

    def create_template(name)
      template_file = File.join(@base_dir, "views", "#{name}.html.erb")
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
          @drilldown_result = drilldown_items(entries)
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
          @drilldown_result = drilldown_items(result)
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
        @query = nil
        @version = nil
        @type = nil
        parameters.each do |parameter|
          key, value = parameter.split(/:/, 2)
          unescaped_value = URI.unescape(value).gsub(/\+/, ' ').strip
          unescaped_value.force_encoding("UTF-8")
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
            target = (record["name"] | record["signature"] | record["description"])
            target.match(@query, :allow_update => false)
          end
        end
        if @version
          conditions << Proc.new do |record|
            record["version"] == @version
          end
        end
        if @type
          conditions << Proc.new do |record|
            record["type"] == @type
          end
        end
        conditions
      end

      def drilldown_items(entries)
        result = []
        result << [:version, drilldown_item(entries, "version", "_key")]
        result << [:class, drilldown_item(entries, "class", "name")]
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
        label = entry.name
        signature = entry.signature
        if signature
          label = label.sub(/(\.?#).+\z/, '\1') + signature
        end
        a(h(label).gsub(/(::|\.|\.?#|\(\|\)|,|_)/, "<wbr />\\1<wbr />"),
          entry_href(entry))
      end

      def entry_href(entry)
        mapper = url_mapper(entry.version.key)
        case entry.type.key
        when "class"
          mapper.class_url(entry.name)
        when "constant", "variable", "instance method", "singleton method"
          mapper.method_url(entry.name)
        else
          "/#{entry.type.key}"
        end
      end

      def link_type(entry)
        a(h(type_label(entry)), "./type:#{u(entry.type.key)}/")
      end

      TYPE_LABEL = {
        "class" => "クラス",
        "instance-method" => "インスタンスメソッド",
        "singleton-method" => "シングルトンメソッド",
        "module-function" => "モジュールファンクション",
        "constant" => "定数",
      }
      def type_label(entry)
        type = entry.type.key
        TYPE_LABEL[type] || type
      end

      def link_version(entry)
        a(h(entry.version.key), "./version:#{u(entry.version.key)}/")
      end

      def format_description(entry)
        @snippet ||= @expression.snippet(["<span class=\"keyword\">",
                                          "</span>"],
                                         :normalize => true,
                                         :width => 140)
        description = remove_markup(entry.description)
        snippet_description = nil
        if @snippet and description
          snippets = @snippet.execute(h(description))
          unless snippets.empty?
            separator = tag("span", {:class => "separator"}, "...")
            snippets = snippets.collect do |snippet|
              auto_spec_link(snippet)
            end
            snippets << ""
            snippets.unshift("")
            snippet_description = snippets.join(separator)
          end
        end
        snippet_description ||= auto_spec_link(h(description))
        tag("div", {:class => "snippet"}, snippet_description)
      end

      def remove_markup(source)
        return nil if source.nil?
        source.gsub(/\[\[.+?:(.+?)\]\]/, '\1')
      end

      def auto_spec_link(text)
        @database.specs.tag_keys(text) do |record, word|
          if word == @query
            word
          else
            a(word, "./query:#{u(word)}/")
          end
        end
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
    end
  end
end
