

Gem::Specification.new do |s|
  s.name              = "airplay"
  s.version           = 0.1
  s.summary           = "Airplay client"
  s.description       = "Send image/video to an airplay enabled device"
  s.authors           = ["elcuervo"]
  s.email             = ["yo@brunoaguirre.com"]
  s.homepage          = "http://github.com/elcuervo/airplay"
  s.files = ["lib/airplay/client.rb", "lib/airplay/node.rb", "lib/airplay/protocol/image.rb", "lib/airplay/protocol/video.rb", "lib/airplay/protocol.rb", "lib/airplay/version.rb", "lib/airplay.rb"]
  s.add_dependency("dnssd")
  s.add_development_dependency("cutest")
  s.add_development_dependency("capybara")
end
