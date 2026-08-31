# mruby build config for the SANITIZED (fuzzing) build.
#
# Builds libmruby.a with $SANITIZER_FLAGS (ASan+UBSan, halting) + $DEBUG_FLAGS (DWARF <= 3)
# + $FUZZ_COV (-fsanitize=fuzzer-no-link).  The last one matters: SANITIZER_FLAGS carries NO
# SanitizerCoverage, so without it libmruby.a gets no edge counters and libFuzzer/Mayhem run
# BLIND over the library (targets execute but report edges=0 forever) — instrumentation is a
# per-TU COMPILE flag, `-fsanitize=fuzzer` at LINK only supplies the runtime.
#
# The flags are APPENDED to mruby's toolchain defaults (do not export CFLAGS/LDFLAGS around
# rake — mruby's gcc/clang toolchain REPLACES its whole default flag list with $CFLAGS).
#
# No tests here: the oracle build (build_config_test.rb) owns those.
MRuby::Build.new('fuzz') do |conf|
  conf.toolchain :clang

  conf.gembox 'default'

  extra = [ENV['SANITIZER_FLAGS'], ENV['DEBUG_FLAGS'], ENV['FUZZ_COV']].compact.join(' ').split
  unless extra.empty?
    [conf.cc, conf.cxx, conf.objc, conf.asm].each {|c| c.flags += extra }
    conf.linker.flags += extra
  end
end
