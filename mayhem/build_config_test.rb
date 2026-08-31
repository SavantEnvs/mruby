# mruby build config for the FUNCTIONAL-TEST (oracle) build.
#
# Plain, uninstrumented build with mruby's own default toolchain flags, plus the mruby-test
# gem (conf.enable_test) so `rake test:build` produces build/oracle/bin/mrbtest — the real
# upstream assertion suite that mayhem/test.sh runs.  Kept completely separate from the
# sanitized fuzz build (build/fuzz) so the oracle never false-fails on benign UB and the two
# builds can both be re-run incrementally (idempotent build.sh).
#
# $COVERAGE_FLAGS (empty by default) is appended so a coverage build can measure how much of
# the project the suite exercises.
MRuby::Build.new('oracle') do |conf|
  conf.toolchain :clang

  conf.gembox 'default'

  cov = (ENV['COVERAGE_FLAGS'] || '').split
  unless cov.empty?
    [conf.cc, conf.cxx, conf.objc, conf.asm].each {|c| c.flags += cov }
    conf.linker.flags += cov
  end

  conf.enable_test
end
