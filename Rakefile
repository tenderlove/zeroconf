require "bundler"
require "bundler/gem_tasks"
require "rake/testtask"

Bundler::GemHelper.install_tasks

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList['test/*_test.rb']
  t.warning = true
end
