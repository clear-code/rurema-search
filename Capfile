require 'capistrano/setup'
require 'capistrano/deploy'
require 'capistrano/bundler'

require "capistrano/scm/git"
install_plugin Capistrano::SCM::Git

Dir.glob('lib/capistrano/tasks/*.cap').each { |r| import r }
