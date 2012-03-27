Gem::Specification.new do |s|
  s.name              = "airplay"
  s.version           = "0.2.9"
  s.summary           = "Airplay client"
  s.description       = "Send image/video to an airplay enabled device"
  s.authors           = ["elcuervo"]
  s.email             = ["yo@brunoaguirre.com"]
  s.homepage          = "http://github.com/elcuervo/airplay"
  s.files             = `git ls-files`.split("\n")
  s.test_files        = `git ls-files test`.split("\n")

  s.add_dependency("dnssd", "~> 2.0")
  s.add_dependency("net-http-persistent", ">= 2.6")
  s.add_dependency("net-http-digest_auth", "~> 1.2")

  s.add_development_dependency("cutest", "~> 1.1")
  s.add_development_dependency("capybara", "~> 1.0")
  s.add_development_dependency("fakeweb", "~> 1.3")
  s.add_development_dependency("vcr", "~> 2.0")
end
