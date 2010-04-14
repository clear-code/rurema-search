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
        context = SearchContext.new(@database, request)
        context.handle
        response.write(template.result(context.instance_eval {binding}))
      end
      response.to_a
    end

    private
    def template
      @template ||= create_template
    end

    def create_template
      template_file = File.join(@base_dir, "views", "search.html.erb")
      erb = ERB.new(File.read(template_file), 0, "%<>")
      erb.filename = template_file
      erb
    end

    class SearchContext
      def initialize(database, request)
        @database = database
        @request = request
      end

      def handle
        start = Time.now.to_i
        _, *parameters = @request.path_info.split(/\//)
        @query = ''
        @version = nil
        parameters.each do |parameter|
          key, value = parameter.split(/:/, 2)
          case key
          when "query"
            @query = URI.unescape(value)
          when "version"
            @version = value
          end
        end
        entries = @database.entries
        if @query.empty?
          @n_entries = entries.size
          @drilldown_result = drilldown_items(entries)
          @entries = entries.sort(["name"], :limit => 10)
        else
          result = @database.entries.select do |record|
            (record["name"] =~ query) | (record["document"] =~ query)
          end
          @n_entries = result.size
          @drilldown_result = drilldown_items(result)
          @entries = result.sort(["_nsubrecs"], :limit => 10)
        end
        @elapsed_time = Time.now.to_f - start.to_f
      end

      private
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
    end
  end
end
