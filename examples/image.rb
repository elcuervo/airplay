require "airplay"

Airplay.use "corax", "corax"
Airplay.configure do |c|
  c.log_level = "debug"
end

Airplay.view("http://fitdeck.com/Portals/24254/images/Sunrise.jpg")
sleep 4
