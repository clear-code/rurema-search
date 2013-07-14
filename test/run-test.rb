#!/usr/bin/env ruby
#
# Copyright (C) 2010-2013  Kouhei Sutou <kou@clear-code.com>
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

$VERBOSE = true

$KCODE = "u" if RUBY_VERSION < "1.9"

base_dir = File.expand_path(File.join(File.dirname(__FILE__), ".."))
bitclust_dir = File.expand_path(File.join(base_dir, "..", "bitclust"))
bitclust_lib_dir = File.join(bitclust_dir, "lib")
lib_dir = File.join(base_dir, "lib")
test_dir = File.join(base_dir, "test")

require "test-unit"
require "test/unit/notify"

ARGV.unshift("--priority-mode")
ARGV.unshift(File.join(test_dir, "test-unit.yml"))
ARGV.unshift("--config")

$LOAD_PATH.unshift(bitclust_lib_dir)

$LOAD_PATH.unshift(lib_dir)

$LOAD_PATH.unshift(test_dir)
require "rurema-search-test-utils"

exit Test::Unit::AutoRunner.run(true, test_dir)
