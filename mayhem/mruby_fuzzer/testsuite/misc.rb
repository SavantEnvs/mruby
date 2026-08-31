module M; def self.z; [1,2,3].map { _1 * 2 }; end; end
p M.z
p [1,2,3].pack("C*").unpack("C*")
