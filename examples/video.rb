require "airplay"

Airplay.use "Apple TV"

video = "http://trailers.apple.com/movies/marvel/ironman3/ironman3-tlr1-m4mb0_h1080p.mov"

Airplay.play video
puts "Starts playing: #{video}"

Airplay.player.progress do |status|
  if status["readyToPlay"]
    total = status["duration"]
    current = status["position"]
    percent = (current*100/total).round

    print "\r|#{"=" * percent}> #{percent}%"
  end
end

Airplay.player.wait
puts "Video playback finished!"
