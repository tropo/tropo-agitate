ENV['RUBY_FLAGS'] = "-I#{%w(lib spec).join(File::PATH_SEPARATOR)}"

require 'rubygems'
gem 'rspec', '>= 2.3.0'
require 'rspec/core/rake_task'

task :default => :spec

RSpec::Core::RakeTask.new do |t|
  t.rspec_opts = '--color'
end

gem 'ci_reporter'
require 'ci/reporter/rake/rspec'
task :ci => ['ci:setup:rspec', :spec]
