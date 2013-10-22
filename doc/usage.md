## Usage

### CLI

#### View devices

`air list`
```text
* Apple TV (AppleTV2,1 running 11A502)
  ip: 192.168.1.12
  resolution: 1280x720
```

#### Play a video

`air play [url to video or local file]`
```text
Playing http://movietrailers.apple.com/movies/universal/rush/rush-tlr3_480p.mov?width=848&height=352
Time: 00:00:13 [=====                                              ] 7% Apple TV
```

### Show images

`air view [url to image or image folder]`

### Library

#### Configuration

```ruby
Airplay.configure do |config|
  config.log_level      # Log4r levels (Default: Log4r::ERROR)
  config.autodiscover   # Allows to search for nodes (Default: true)
  config.host           # In which host bind the server for the assets (Default: 0.0.0.0)
  config.port           # In which port bind the server for the assets (Default: 1337)
  config.output         # Where to log (Default: Log4r::Outputter.stdout)
end
```

#### Devices

```ruby
require "airplay"

Airplay.devices.each do |device|
  puts device.name
end

# You can access an know device easily
device = Airplay["Apple TV"]

# Or you can group known devices to have them do a given action toghether
Airplay.group["Backyard"] << Airplay["Apple TV"]
Airplay.group["Backyard"] << Airplay["Room TV"]

# The groups can later do some actions like:
Airplay.group["Backyard"].play("video")
```

#### Images

```ruby
require "airplay"

apple_tv = Airplay["Apple TV"]

# You can send local files
apple_tv.view("my_image.png")

# Or use remote files
apple_tv.view("https://github.com/elcuervo/airplay/raw/master/doc/img/logo.png")

# And define a transition
apple_tv.view("url_to_the_image", transition: "Dissolve")

# View all transitions
apple_tv.transitions
```

#### Video

```ruby
require "airplay"

apple_tv = Airplay["Apple TV"]
trailer = "http://movietrailers.apple.com/movies/dreamworks/needforspeed/needforspeed-tlr1xxzzs2_480p.mov"

player = apple_tv.play(trailer)
```

##### Playlist

```ruby
# You can also add videos to a playlist and let the library handle them
player.playlist << "video_url"
player.playlist << "video_path"

# Or control it yourself
player.next
player.previous
```

##### Player

```ruby
# Wait until the video is finished
player.wait

# Actions
player.pause
player.resume
player.stop
player.scrub

# Access the playback time per second
player.progress -> progress {
  puts "I'm viewing #{progress.position} of #{progress.duration}"
}
```
