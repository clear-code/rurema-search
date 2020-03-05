set :application, 'rurema-search'
set :repo_url, 'https://github.com/ruby/rurema-search'
set :branch, 'ro'
set :deploy_to, '/var/rubydoc/rurema-search'

set :default_env, {
  'PATH' => '/snap/bin:$PATH',
}

set :linked_files, %w{document.yaml production.yaml}
set :linked_dirs, %w{groonga-database var/lib/suggest}

namespace :deploy do
  desc 'Restart application'
  task :restart do
    on roles(:app), in: :sequence, wait: 5 do
      execute :touch, release_path.join('tmp/restart.txt')
    end
  end
  after :publishing, :restart
end
