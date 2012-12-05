module Airplay
  class Node
    class Info < Structure.new(:deviceid, :features, :model, :srcvers)
    end
  end
end
