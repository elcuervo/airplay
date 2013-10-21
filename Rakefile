$: <<  File.expand_path("../lib", __FILE__)

require "rake/testtask"
require "rake/name_space"
require "fileutils"
require "airplay/version"
require "airplay/cli/version"

Rake::TestTask.new("spec") do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
end

def build_gem(gemspec_name, version)
  gem_name = "#{gemspec_name}-#{version}.gem"

  FileUtils.mkdir_p("pkg")
  `gem build #{gemspec_name}.gemspec`
  FileUtils.mv(gem_name, "pkg")

  puts "#{gemspec_name} (v#{version}) builded!"

  "./pkg/#{gem_name}"
end

def release_gem(gemspec_name, version)
  gem_path = build_gem(gemspec_name, version)
  `gem push #{gem_path}`

  puts "#{gem_path} released!"
end

def install_gem(gemspec_name, version)
  gem_path = build_gem(gemspec_name, version)
  `gem install --local #{gem_path}`

  puts "#{gem_path} installed!"
end

namespace :build do
  task(:lib) { build_gem("airplay", Airplay::VERSION) }
  task(:cli) { build_gem("airplay-cli", Airplay::CLI::VERSION) }
  task(:all) {
    Rake::Task["build:lib"].invoke
    Rake::Task["build:cli"].invoke
  }
end

namespace :install do
  task(:lib) { install_gem("airplay", Airplay::VERSION) }
  task(:cli) { install_gem("airplay-cli", Airplay::CLI::VERSION) }
  task(:all) {
    Rake::Task["install:lib"].invoke
    Rake::Task["install:cli"].invoke
  }
end

namespace :release do
  task(:lib) { release_gem("airplay", Airplay::VERSION) }
  task(:cli) { release_gem("airplay-cli", Airplay::CLI::VERSION) }
  task(:all) {
    Rake::Task["release:lib"].invoke
    Rake::Task["release:cli"].invoke
  }
end

task :default => [:test]
task :test => [:spec]
