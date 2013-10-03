require "airplay"

puts Airplay.nodes.count
Airplay.nodes.each do |node|
  puts node.name
end

video = "http://trailers.apple.com/movies/marvel/ironman3/ironman3-tlr1-m4mb0_h1080p.mov"

apple_tv = Airplay["Apple TV"]
player = apple_tv.play(video)
player.progress -> info {
}
player.wait

Airplay.group["Backyard"] << Airplay["Pool TV"]
Airplay.group["Backyard"] << Airplay.nodes.add("BBQTV", "192.168.1.12")

player = Airplay.group["Backyard"].play("video")
player.wait

Airplay.all # => Alias for a global group of all the available nodes
