# Airplay

![Travis](https://secure.travis-ci.org/elcuervo/airplay.png)

![Ruby Airplay](https://github.com/elcuervo/elcuervo.github.com/raw/master/images/posts/airplay/ruby_airplay.png)

A client (and someday a server) of the superfancy http content stream technique
that Apple uses in its products.

Now supports any Airplay-compatible device, like [Airserver](http://www.airserverapp.com/)

You can try this in an AppleTV for instance.

## IMPORTANT!

Since iOS 5 there are some changes in the API so to keep playing something (like
a video) you must keep the client alive!

## Basic Usage

```ruby
require 'airplay'

airplay = Airplay::Client.new
# To send an image
airplay.send_image("fancy_pants.jpg")

# To stream a video
airplay.send_video("http://www.yo-yo.org/mp4/yu2.mp4")
```

## Sending images

```ruby
require 'airplay'

airplay = Airplay::Client.new

airplay.send_image("fancy_pants.jpg")
airplay.send_image(File.open("/home/userman/Pictures/fancy_pants.jpg"))
airplay.send_image("http://mine.icanhascheezburger.com/completestore/Wezinyercupz128401525895963750.jpg")
```

### Transitions

```ruby
require 'airplay'

airplay = Airplay::Client.new

airplay.send_image("fancy_pants.jpg", :dissolve)
airplay.send_image("fancy_pants.jpg", :slide_left)
airplay.send_image("fancy_pants.jpg", :slide_right)
```

## Scrub

```ruby
require 'airplay'

airplay = Airplay::Client.new
airplay.scrub
# {:duration => 189, :position => 50}
airplay.scrub(30) # Media goes to 30s
airplay.scrub("10%") # Media goes to the 10% of its duration
```

## Password Authentication

```ruby
require 'airplay'

airplay = Airplay::Client.new
airplay.use "Apple TV"
airplay.password "password"

airplay.send_image("lolcatz.jpg")
```

## Player

```ruby
require 'airplay'

airplay = Airplay::Client.new
player = airplay.send_video("http://www.yo-yo.org/mp4/yu2.mp4")
player.pause
player.resume
player.scrub
# {:duration => 189, :position => 50}
player.scrub("50%") # Go to the half of the media
player.stop
```

## Useful methods

```ruby
require 'airplay'

airplay = Airplay::Client.new
airplay.browse
#=> [#<Airplay::Node:0x007fbb5a83eb28 @name="elCuervo", @domain="local.", @ip="10.1.0.63">, #<Airplay::Node:0x007fbb5a83b0b8 @name="Apple TV", @domain="local.", @ip="10.1.0.220">]
airplay.use "elCuervo"
airplay.use "Apple TV"
```

## Contributors

Thanks to all the contributors:

  * File handler support when sending an image. By [pote](http://github.com/pote)
