require "test_helper"
require "airplay/player/media"

test "finding if a media is compatible" do
  media = Airplay::Player::Media.new("test.mov")
  assert media.compatible?
end

test "finding if a media is not compatible" do
  media = Airplay::Player::Media.new("test.psd")
  assert !media.compatible?
end
