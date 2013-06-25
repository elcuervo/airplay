require "rake/testtask"

Rake::TestTask.new("spec") do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
end

task :default => [:test]
task :test => [:spec]
