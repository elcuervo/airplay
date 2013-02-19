require "airplay"

Airplay.use "Apple TV"
Airplay.play "http://static.bouncingminds.com/ads/30secs/country_life_butter.mp4"
Airplay.player.progress do |status|
  puts status
end
Airplay.player.wait
