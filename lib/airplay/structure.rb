
class Structure < Struct
  def self.create(hash)
    new(*members.map { |member| hash[member.to_sym] })
  end
end
