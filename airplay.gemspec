$: <<  File.expand_path("../lib", __FILE__)
require "airplay/version"

Gem::Specification.new do |s|
  s.name         = "airplay"
  s.version      = Airplay::VERSION
  s.summary      = "Airplay library"
  s.description  = "Send image/video to an airplay enabled device."
  s.licenses     = ["MIT", "HUGWARE"]
  s.authors      = ["elcuervo"]
  s.email        = ["elcuervo@eluervo.net"]
  s.homepage     = "http://github.com/elcuervo/airplay"
  s.files        = `git ls-files`.split("\n")
  s.test_files   = `git ls-files test`.split("\n")

  s.add_dependency("dnssd",                "~> 3.0")
  s.add_dependency("CFPropertyList",       "~> 2.2")
  s.add_dependency("mime-types",           ">= 1.16")
  s.add_dependency("logging",              "~> 2.0.0")
  s.add_dependency("cuba",                 "~> 3.8.0")
  s.add_dependency("micromachine",         "~> 1.0.4")
  s.add_dependency("net-http-digest_auth", "~> 1.2.1")
  s.add_dependency("http_parser.rb",       "~> 0.6.0")

  s.add_development_dependency("cutest",  "~> 1.2.3")
  s.add_development_dependency("fakeweb", "~> 1.3.0")
  s.add_development_dependency("vcr",     "~> 2.4.0")
end
