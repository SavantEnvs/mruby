class A < Struct.new(:x, :y)
  def to_s; "#{x},#{y}"; end
end
puts A.new(1,2)
