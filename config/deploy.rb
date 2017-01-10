set :application, 'rurema-search'
set :repo_url, 'git@github.com:ruby/rurema-search.git'
set :branch, 'ro'
set :deploy_to, '/var/rubydoc/rurema-search'

set :linked_files, %w{document.yaml production.yaml}
set :linked_dirs, %w{groonga-database var/lib/suggest}

set :rbenv_type, :user
set :rbenv_path, '/home/rurema/.rbenv'
set :rbenv_ruby, '2.3.3'

namespace :deploy do
  desc 'Restart application'
  task :restart do
    on roles(:app), in: :sequence, wait: 5 do
      execute :touch, release_path.join('tmp/restart.txt')
    end
  end
  after :publishing, :restart
end
