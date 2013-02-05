# Public: Stupid class to easily create and initialize a Struct from a hash
#
class Structure < Struct
  def self.create(hash)
    new(*members.map { |member| hash[member.to_sym] })
  end
end
