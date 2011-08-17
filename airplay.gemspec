Gem::Specification.new do |s|
  s.name              = "airplay"
  s.version           = "0.1.1"
  s.summary           = "Airplay client"
  s.description       = "Send image/video to an airplay enabled device"
  s.authors           = ["elcuervo"]
  s.email             = ["yo@brunoaguirre.com"]
  s.homepage          = "http://github.com/elcuervo/airplay"
  s.files             = `git ls-files`.split("\n")
  s.test_files         = `git ls-files spec`.split("\n")

  s.add_dependency("dnssd")
  s.add_development_dependency("cutest")
  s.add_development_dependency("capybara")
end
