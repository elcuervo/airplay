require "test_helper"
require "airplay/player/media"

describe Airplay::Player::Media do
  context "finding if a media is compatible" do
    Given(:media) { Airplay::Player::Media.new("test.mov") }
    When(:compatibility) { media.compatible? }
    Then { compatibility == true }
  end

  context "finding if a media is not compatible" do
    Given(:media) { Airplay::Player::Media.new("test.psd") }
    When(:compatibility) { media.compatible? }
    Then { compatibility == false }
  end
end
