$: << File.expand_path("../lib", __FILE__)
require "airplay/cli/version"

Gem::Specification.new do |s|
  s.name         = "airplay-cli"
  s.version      = Airplay::CLI::VERSION
  s.summary      = "Airplay CLI"
  s.description  = "Send pics and videos using the terminal"
  s.executables  = "air"
  s.licenses     = ["MIT", "HUGWARE"]
  s.authors      = ["elcuervo"]
  s.email        = ["yo@brunoaguirre.com"]
  s.homepage     = "http://github.com/elcuervo/airplay"

  s.files        = %w(bin/air lib/airplay/cli.rb lib/airplay/cli/version.rb)
  s.require_paths = ["lib"]

  s.required_ruby_version = ">= 4.0"

  s.add_dependency("airplay", ">= 1.0.5")
end
