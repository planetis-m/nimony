# Middle fixture for tests/nimony/opt/topt_cross_module_summary.nim.
# During `shoggoth c`, every proc here calls into `mcrosssummary_leaf`, so its
# intra-module `(smry ...)` carries `callsUnknown`. During `shoggoth opt`,
# cross-module summary resolution refines `midRo` to read-only while keeping
# `midBump` and `midFlip` writing.

import mcrosssummary_leaf

proc midRo*(x: int): int {.noinline.} =
  if x < -100000:
    leafAbort(1)
  result = leafHash(x) + 1

proc midBump*(p: ptr int) {.noinline.} =
  leafBump(p)

proc midFlip*(p: ptr bool) {.noinline.} =
  leafFlip(p)
