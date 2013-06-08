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
    assert_paginate(nil)
  end

  def test_no_paginate
    visit "/type:object/"
    assert_paginate(nil)
  end

  def test_two_pages
    visit "/type:instance-method/class:Object/"
    assert_paginate([["paginate-text", nil, "<<"],
                     ["paginate-current", nil, "1"],
                     ["paginate-link", "?page=2", "2"],
                     ["paginate-link", "?page=3", "3"],
                     ["paginate-link", "?page=2", ">"],
                     ["paginate-link", "?page=3", ">>"]])
  end

  def test_border_hits
    visit "/version:1.9.1/type:constant/?n_entries=10"
    assert_paginate([["paginate-text", nil, "<<"],
                     ["paginate-current", nil, "1"],
                     ["paginate-link", "?page=2;n_entries=10", "2"],
                     ["paginate-link", "?page=3;n_entries=10", "3"],
                     ["paginate-text", nil, "..."],
                     ["paginate-link", "?page=2;n_entries=10", ">"],
                     ["paginate-link", "?page=238;n_entries=10", ">>"]])
  end

  private
  def assert_paginate(expected)
    actual = nil
    # There are 2 paginate div on top and bottom
    paginate = page.all(:xpath, "//div[@class='paginate']")
    unless paginate.empty?
      actual = paginate.first.all(:css, "span").collect do |node|
        a = node.all(:css, "a")
        if a.empty?
          [node["class"], nil, node.text]
        else
          [node["class"], a.first["href"], a.first.text]
        end
      end
    end
    assert_equal(expected, actual)
  end
end
