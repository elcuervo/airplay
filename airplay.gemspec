Gem::Specification.new do |s|
  s.name         = "airplay"
  s.version      = "1.0.0.beta1"
  s.summary      = "Airplay client"
  s.description  = "Send image/video to an airplay enabled device"
  s.executables  = "air"
  s.licenses     = ["MIT", "HUGWARE"]
  s.authors      = ["elcuervo"]
  s.email        = ["yo@brunoaguirre.com"]
  s.homepage     = "http://github.com/elcuervo/airplay"
  s.files        = `git ls-files`.split("\n")
  s.test_files   = `git ls-files test`.split("\n")

  # Lib
  s.add_dependency("dnssd",                "~> 2.0")
  s.add_dependency("uuid",                 "~> 2.3.6")
  s.add_dependency("CFPropertyList",       "~> 2.2.0")
  s.add_dependency("log4r",                "~> 1.1.10")
  s.add_dependency("cuba",                 "~> 3.1.0")
  s.add_dependency("micromachine",         "~> 1.0.4")
  s.add_dependency("celluloid",            "~> 0.15.0")
  s.add_dependency("net-ptth",             "~> 0.0.9")
  s.add_dependency("net-http-digest_auth", "~> 1.2.1")

  # CLI
  s.add_dependency("clap",                 "~> 1.0.0")
  s.add_dependency("ruby-progressbar",     "~> 1.2.0")

  s.add_development_dependency("minitest",  "~> 4.4.0")
  s.add_development_dependency("fakeweb",   "~> 1.3.0")
  s.add_development_dependency("vcr",       "~> 2.4.0")
end
