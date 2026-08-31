begin
  raise ArgumentError, "x"
rescue => e
  p e.message
ensure
  p :done
end
