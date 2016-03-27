# -*- coding: utf-8 -*-
# Copyright (C) 2010  Kouhei Sutou <kou@clear-code.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

class OpenSearchTest < Test::Unit::TestCase
  include RuremaSearchTestUtils
  include ERB::Util

  def test_top_level_open_search_description
    visit "/open_search_description.xml"
    assert_open_search_description("#{host}/")
  end

  def test_versioned_open_search_description
    visit "/version:1.8.8/open_search_description.xml"
    assert_open_search_description("#{host}/version:1.8.8/")
  end

  private
  def assert_open_search_description(expected_template)
    content_type = page.response_headers["Content-Type"]
    assert_equal("application/opensearchdescription+xml",
                 content_type)
    xml = Nokogiri::XML(page.source)
    url = xml.xpath("//node()[name()='Url']")[0]
    assert_equal("#{expected_template}?query={searchTerms}", url["template"])
  end
end
