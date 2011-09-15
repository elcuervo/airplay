task :test do
  require "cutest"
  require "capybara/dsl"

  Cutest.run(Dir["test/*.rb"])

  class Cutest::Scope
    include Capybara::DSL
  end
end

task :default => :test
