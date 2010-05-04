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

class NormalizePathTest < Test::Unit::TestCase
  include RuremaSearchTestUtils
  include ERB::Util

  def test_root
    assert_normalize("/", "/")
  end

  def test_no_slash
    assert_normalize("/version:1.9.2/", "/version:1.9.2/")
  end

  def test_slash
    assert_normalize("/library:webrick%2Fserver/",
                     "/library:webrick/server/")
  end

  def test_mixed
    assert_normalize("/version:1.9.2" +
                     "/singleton-method:#{u('WEBrick::GenericServer.new')}" +
                     "/type:singleton-method" +
                     "/library:#{u('webrick/server')}/",
                     "/version:1.9.2" +
                     "/singleton-method:WEBrick::GenericServer.new" +
                     "/type:singleton-method" +
                     "/library:webrick/server/")
  end

  private
  def assert_normalize(expected, path)
    assert_equal(expected, app.send(:normalize_path, path))
  end
end
