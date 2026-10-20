require "rake/testtask"

Rake::TestTask.new("test:unit") do |task|
  task.libs << "test"
  task.pattern = "test/unit/**/*_test.rb"
end

Rake::TestTask.new("test:protocol") do |task|
  task.libs << "test"
  task.pattern = "test/protocol/**/*_test.rb"
end

Rake::TestTask.new("test:hardware") do |task|
  task.libs << "test"
  task.pattern = "test/hardware/**/*_test.rb"
end

task "test:all" => %w[test:unit test:protocol test:hardware]
task default: %w[test:unit test:protocol]

namespace :doc do
  task :generate do
    structure = %w[
      header toc installation usage discovery protocol development testing documentation contributors
    ]

    File.open("README.md", "w") do |file|
      structure.each { |part| file << File.read("doc/#{part}.md") << "\n" }
    end
  end
end

namespace :build do
  task :all do
    sh "gem build airplay.gemspec"
    sh "gem build airplay-cli.gemspec"
  end
end
