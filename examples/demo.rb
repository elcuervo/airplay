require "airplay"

Airplay.browse
puts Airplay.nodes.count
Airplay.nodes.each do |node|
  puts node.address
end

apple_tv = Airplay["Apple TV"]
require 'ruby-debug';debugger;1
player = apple_tv.play("video")
player.progress do |info|
end

Airplay.group["Backyard"] << Airplay["Pool TV"]
Airplay.group["Backyard"] << Airplay.nodes.add("BBQTV", "192.168.1.12")

player = Airplay.group["Backyard"].play("video")
player.wait

Airplay.all # => Alias for a global group of all the available nodes
