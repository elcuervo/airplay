module Airplay
  class Node
    # Public: Simple class to represent information of a Node
    #
    class Info < Structure.new(:deviceid, :features, :model, :srcvers)
    end
  end
end
