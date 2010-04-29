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

class PaginateTest < Test::Unit::TestCase
  include RuremaSearchTestUtils

  def test_get
    visit "/"
    assert_paginate([["paginate-text", nil, "<<"],
                     ["paginate-current", nil, "1"],
                     ["paginate-link", "?page=2", "2"],
                     ["paginate-link", "?page=3", "3"],
                     ["paginate-text", nil, "..."],
                     ["paginate-link", "?page=2", ">"],
                     ["paginate-link", "?page=7", ">>"]])
  end

  def test_no_paginate
    visit "/type:class/"
    assert_paginate(nil)
  end

  def test_two_pages
    visit "/type:singleton-method/"
    assert_paginate([["paginate-text", nil, "<<"],
                     ["paginate-current", nil, "1"],
                     ["paginate-link", "?page=2", "2"],
                     ["paginate-link", "?page=2", ">"],
                     ["paginate-link", "?page=2", ">>"]])
  end

  def test_border_hits
    visit "/version:1.9.2/type:singleton-method/?n_entries=10"
    assert_paginate([["paginate-text", nil, "<<"],
                     ["paginate-current", nil, "1"],
                     ["paginate-link", "?page=2", "2"],
                     ["paginate-link", "?page=3", "3"],
                     ["paginate-text", nil, "..."],
                     ["paginate-link", "?page=2", ">"],
                     ["paginate-link", "?page=6", ">>"]])
  end

  private
  def assert_paginate(expected)
    paginate = current_dom.xpath("//div[@class='paginate']")[0]
    if paginate
      actual = paginate.xpath("span").collect do |node|
        a = node.xpath("a")[0]
        [node["class"], a ? a["href"] : nil, node.text]
      end
    else
      actual = nil
    end
    assert_equal(expected, actual)
  end
end
