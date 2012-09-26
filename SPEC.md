# Airplay Spec

## CLI

### Commands

**play**
**stop**
**pause**

```bash
  airplay image.jpg
  airplay image.jpg --transition slide_left

  airplay video.mp4
  airplay> pause
```

## Library

```ruby
  Airplay.send("image.png", transition: :slide_left)

  player = Airplay.send("video.mp4")
  player.pause
  player.rewind("10s")

  Airplay.player
```

## Documentation

* http://nto.github.com/AirPlay.html
* http://elcuervo.co/protocol/airplay/apple/2012/01/05/airplay-protocol.html
