require 'airplay'

client = Airplay::Client.new
client.send_image(File.join(File.dirname(__FILE__), "jobs.jpg"))
sleep(10)
