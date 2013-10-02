module Airplay
  # Public: Represents an Airplay Node
  #
  class Node
    # Public: Simple class to represent information of a Node
    #
    Info = Structure.new(:deviceid, :features, :model, :srcvers)
  end
end
