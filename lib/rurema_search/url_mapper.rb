# Copyright (c) 2010 Kouhei Sutou <kou@clear-code.com>
#
# License: LGPLv3+

module RuremaSearch
  class URLMapper < BitClust::URLMapper
    def initialize(options)
      super
      @version = options[:version]
    end

    def base_url
      "#{@base_url}#{@version}/"
    end

    def css_url
      "#{base_url}style.css"
    end

    def custom_css_url(css)
      "#{base_url}#{css}"
    end

    def js_url
      "#{base_url}t.js"
    end

    def custom_js_url(js)
      "#{base_url}#{js}"
    end

    def favicon_url
      "#{base_url}rurema.png"
    end

    def library_index_url
      "#{base_url}library/"
    end

    def library_url(name)
      if name == "/"
        library_index_url
      else
        "#{base_url}library/#{encodename_url(name)}.html"
      end
    end

    def class_url(name)
      "#{base_url}class/#{encodename_url(name)}.html"
    end

    def method_url(spec)
      cname, tmark, mname = *split_method_spec(spec)
      "#{base_url}method/#{encodename_url(cname)}/#{typemark2char(tmark)}/#{encodename_url(mname)}.html"
    end

    def function_index_url
      "#{base_url}function/"
    end

    def function_url(name)
      "#{base_url}function/#{name}"
    end

    def opensearchdescription_url
      "#{base_url}open_search_description.xml"
    end

    def search_url
      "#{base_url}search"
    end

    def spec_url(name)
      "#{base_url}spec/#{name}.html"
    end

    def document_url(name)
      "#{base_url}doc/#{encodename_url(name)}.html"
    end
  end
end
