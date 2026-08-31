def f(a, b=2, *c, &d)
  a.times { |i| yield i }
end
f(3) { |x| p x }
