# Airplay

![Airplay](test/fixtures/files.logo.png)

# WARNING: THIS IS WORK IN PROGRESS REWRITE

## Sending images

```ruby
require "airplay"

Airplay.view("my_superhero.png")
```

## Playing video

```
Airplay.play("http://static.bouncingminds.com/ads/15secs/dogs_600.mp4")

# Wait until the video is finished
Airplay.player.wait

# Actions
Airplay.player.pause
Airplay.player.resume
Airplay.player.stop
Airplay.player.scrub

# Access the playback time per second
Airplay.player.progress do |progress|
  puts "I'm viewing #{progress["position"]} of #{progress["duration"]}"
end
```

## Contributors

* [sodabrew](http://github.com/sodabrew)
* [pote](http://github.com/pote)
