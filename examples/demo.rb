require "airplay"

puts Airplay.devices.count
Airplay.devices.each do |device|
  puts device.name
end

videos = [
  "http://trailers.apple.com/movies/marvel/ironman3/ironman3-tlr1-m4mb0_h1080p.mov",
  "http://movietrailers.apple.com/movies/dreamworks/needforspeed/needforspeed-tlr1xxzzs2_480p.mov"
]

apple_tv = Airplay["Apple TV"]

apple_tv.view("./test/fixtures/files/logo.png", transition: "SlideLeft")
sleep 2
puts apple_tv.view("./test/fixtures/files/a.png", transition: "SlideLeft")
sleep 20
exit

videos.each do |video|
  player = apple_tv.play(video)
  sleep 10
end

Airplay.group["Backyard"] << Airplay["Pool TV"]
Airplay.group["Backyard"] << Airplay.devices.add("BBQTV", "192.168.1.12")

player = Airplay.group["Backyard"].play("video")
player.wait

Airplay.all # => Alias for a global group of all the available devices
