$: << File.expand_path("../lib", __FILE__)
require "airplay/version"

Gem::Specification.new do |s|
  s.name         = "airplay-fake-device"
  s.version      = Airplay::VERSION
  s.summary      = "In-process AirPlay receiver double"
  s.description  = "Dev-only virtual receiver used by the airplay test lanes"
  s.licenses     = ["MIT", "HUGWARE"]
  s.authors      = ["elcuervo"]
  s.email        = ["yo@brunoaguirre.com"]
  s.homepage     = "http://github.com/elcuervo/airplay"

  s.files        = Dir["lib/airplay/fake_device.rb", "lib/airplay/fake_device/**/*.rb"] +
                   %w[lib/airplay/fake_device/NOTES.md]
  s.require_paths = ["lib"]

  s.required_ruby_version = ">= 4.0"

  s.add_dependency("airplay", ">= 1.0.5")
  s.add_dependency("async-http", "~> 0.105")
end
