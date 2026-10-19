$: << File.expand_path("../lib", __FILE__)
require "airplay/version"

Gem::Specification.new do |s|
  s.name         = "airplay"
  s.version      = Airplay::VERSION
  s.summary      = "Airplay client"
  s.description  = "Send image/video to an airplay enabled device"
  s.licenses     = ["MIT", "HUGWARE"]
  s.authors      = ["elcuervo"]
  s.email        = ["yo@brunoaguirre.com"]
  s.homepage     = "http://github.com/elcuervo/airplay"

  s.files        = Dir["lib/**/*.rb"].reject { |file| file.start_with?("lib/airplay/fake_device") } +
                   %w[README.md LICENSE]
  s.require_paths = ["lib"]

  s.required_ruby_version = ">= 4.0"

  s.add_dependency("async",                "~> 2.46")
  s.add_dependency("async-http",           "~> 0.105")
  s.add_dependency("console",              "~> 1.38")
  s.add_dependency("plist",                "~> 3.7")
  s.add_dependency("mime-types",           "~> 3.7")
  s.add_dependency("net-http-digest_auth", "~> 1.4")

  s.add_development_dependency("minitest", "~> 5.25")
  s.add_development_dependency("rake",     "~> 13.4")
end
