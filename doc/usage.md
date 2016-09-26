## Usage

### CLI

#### View devices

`air list`

![air list](doc/img/cli_list.png)

```text
* Apple TV (AppleTV2,1 running 11A502)
  ip: 192.168.1.12
  resolution: 1280x720
```

#### Play a video

`air play [url to video or local file]`

![air play](doc/img/cli_play.png)

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
  config.log_level      # Log level (Default: info)
  config.autodiscover   # Allows to search for nodes (Default: true)
  config.host           # In which host to bind the server (Default: 0.0.0.0)
  config.port           # In which port to bind the server (Default: will find one)
  config.output         # Where to log (Default: stdout)
end
```

#### Devices

```ruby
require "airplay"

Airplay.devices.each do |device|
  puts device.name
end
```

#### Accessing and Grouping

```ruby
# You can access a known device easily
device = Airplay["Apple TV"]

# And add the password of the device if needed
device.password = "my super secret password"

# Or you can group known devices to have them do a given action together
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
player.play

# Or control it yourself
player.next
player.previous

# Or if you prefer you can have several playlists
player = apple_tv.player
player.playlists["Star Wars Classic"] << "Star Wars Episode IV: A New Hope"
player.playlists["Star Wars Classic"] << "Star Wars Episode V: The Empire Strikes Back"
player.playlists["Star Wars Classic"] << "Star Wars Episode VI: Return of the Jedi"

player.playlists["Star Wars"] << "Star Wars Episode I: The Phantom Menace"
player.playlists["Star Wars"] << "Star Wars Episode II: Attack of the Clones"
player.playlists["Star Wars"] << "Star Wars Episode III: Revenge of the Sith"

player.use("Star Wars Classic")
player.play
player.wait
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
player.info
player.seek

# Access the playback time per second
player.progress -> progress {
  puts "I'm viewing #{progress.position} of #{progress.duration}"
}
```
