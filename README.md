# Airplay

![Airplay](test/fixtures/files/logo.png)

Airplay attempts to be compatible with the latest AppleTV firmware but I'd like
to add compatibility to other servers.

## Installation

`gem install airplay`

## CLI

### View nodes

`air list`
```text
* Apple TV (AppleTV2,1 running 11A502)
  ip: 192.168.1.12
  resolution: 1280x720
```

### Play a video

`air play [url to video]`

### Show images

`air view [url to image or image folder]`
```text
Playing http://movietrailers.apple.com/movies/universal/rush/rush-tlr3_480p.mov?width=848&height=352
Time: 00:00:13 [=====                                              ] 7% Apple TV
```

## Library

### Finding nodes

```ruby
require "airplay"

Airplay.nodes.each do |node|
  puts node.name
end
```

### Sending images

```ruby
require "airplay"

apple_tv = Airplay["Apple TV"]
apple_tv.view("my_image.png")
apple_tv.view("url_to_the_image", transition: "Dissolve")

# View all transitions
apple_tv.transitions
```

### Playing video

```ruby
require "airplay"

apple_tv = Airplay["Apple TV"]
trailer = "http://movietrailers.apple.com/movies/dreamworks/needforspeed/needforspeed-tlr1xxzzs2_480p.mov"

player = apple_tv.play(trailer)

# Wait until the video is finished
player.wait

# Actions
player.pause
player.resume
player.stop
player.scrub

# Access the playback time per second
player.progress do |progress|
  puts "I'm viewing #{progress["position"]} of #{progress["duration"]}"
end
```

## Contributors

* [sodabrew](http://github.com/sodabrew)
* [pote](http://github.com/pote)
