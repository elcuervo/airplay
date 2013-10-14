Gem::Specification.new do |s|
  s.name         = "airplay-cli"
  s.version      = "0.1.0.beta1"
  s.summary      = "Airplay client CLI"
  s.description  = "Send pics and videos using the terminal"
  s.executables  = "air"
  s.licenses     = ["MIT", "HUGWARE"]
  s.authors      = ["elcuervo"]
  s.email        = ["yo@brunoaguirre.com"]
  s.homepage     = "http://github.com/elcuervo/airplay"
  s.files        = %w(bin/air lib/airplay/cli.rb)

  s.add_dependency("airplay",              "~> 1.0.0.beta1")
  s.add_dependency("clap",                 "~> 1.0.0")
  s.add_dependency("ruby-progressbar",     "~> 1.2.0")
end
