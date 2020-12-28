# -*- ruby -*-
#
# Copyright (C) 2011-2020  Sutou Kouhei <kou@clear-code.com>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License version 2.1 as published by the Free Software Foundation.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

source "https://rubygems.org/"

gem "rroonga"
gem "racknga"
gem "bitclust-core", github: "rurema/bitclust"
gem "bitclust-dev", github: "rurema/bitclust"

gem 'rack-protection'

group :development, :test do
  gem 'capistrano'
  gem 'capistrano-bundler'
  gem 'rbnacl', '< 5.0.0'
  gem 'rbnacl-libsodium'
  gem 'bcrypt_pbkdf'
  gem "test-unit"
  gem "test-unit-notify"
  gem "test-unit-capybara"
  gem "rake"
end
