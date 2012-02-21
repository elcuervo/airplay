Gem::Specification.new do |s|
  s.name              = "airplay"
  s.version           = "0.2.7"
  s.summary           = "Airplay client"
  s.description       = "Send image/video to an airplay enabled device"
  s.authors           = ["elcuervo"]
  s.email             = ["yo@brunoaguirre.com"]
  s.homepage          = "http://github.com/elcuervo/airplay"
  s.files             = `git ls-files`.split("\n")
  s.test_files        = `git ls-files test`.split("\n")

  s.add_dependency("dnssd")
  s.add_dependency("net-http-persistent")
  s.add_dependency("net-http-digest_auth")

  s.add_development_dependency("cutest")
  s.add_development_dependency("capybara")
  s.add_development_dependency("fakeweb")
  s.add_development_dependency("vcr")
end
