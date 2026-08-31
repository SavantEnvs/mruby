// Preventively disables LeakSanitizer (build-time hook) for every ASan-built target in this
// repo. This fleet fuzzes for memory corruption (ASan) and undefined behavior (UBSan), not
// leaks; LSan findings on a short-lived fuzz harness are typically not actionable defects.
extern "C" int __lsan_is_turned_off() { return 1; }
