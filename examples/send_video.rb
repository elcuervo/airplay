require 'airplay'
require 'ruby-debug'

client = Airplay::Client.new
player = client.send_video("http://www.yo-yo.org/mp4/yu.mp4")
# using player you can play with the video
debugger;1
