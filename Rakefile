$: <<  File.expand_path("../lib", __FILE__)

require "rake/testtask"
require "fileutils"
require "airplay/version"
require "airplay/cli/version"

Rake::TestTask.new("spec") do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
end

class RuleBuilder
  attr_reader :task, :info

  TASKS = [:lib, :cli]

  def initialize(options = {})
    @task = options[:task]

    @info = {
      lib: { name: "airplay", version: Airplay::VERSION },
      cli: { name: "airplay-cli", version: Airplay::CLI::VERSION }
    }
  end

  def construct(action)
    -> n {
      task.call(:all) do
        TASKS.each { |task| Rake::Task["#{action}:#{task}"].invoke }
      end

      TASKS.each do |task_name|
        task.call(task_name) { action_method(action, task_name) }
      end
    }
  end

  private

  def action_method(action, task_name)
    method("#{action}_gem".to_sym).call(task_name)
  end

  def build_gem(type)
    name = info[type][:name]
    version = info[type][:version]

    gem_name = "#{name}-#{version}.gem"

    FileUtils.mkdir_p("pkg")
    `gem build #{name}.gemspec`
    FileUtils.mv(gem_name, "pkg")

    puts "#{name} (v#{version}) builded!"

    "./pkg/#{gem_name}"
  end

  def install_gem(type)
    name = info[type][:name]
    gem_path = build_gem(type)
    `gem install --local #{gem_path}`

    puts "#{gem_path} installed!"
  end

  def release_gem(type)
    name = info[type][:name]
    gem_path = build_gem(type)
    `gem push #{gem_path}`

    puts "#{gem_path} released!"
  end
end

builder = RuleBuilder.new(task: method(:task))
namespace :build,   &builder.construct(:build)
namespace :install, &builder.construct(:install)
namespace :release, &builder.construct(:release)

task :default => [:test]
task :test => [:spec]
