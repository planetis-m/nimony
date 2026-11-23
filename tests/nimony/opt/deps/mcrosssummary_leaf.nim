# Leaf fixture for tests/nimony/opt/topt_cross_module_summary.nim.

import std/syncio

proc leafHash*(x: int): int {.noinline.} =
  result = (x * 5) xor (x + 11)

proc leafBump*(p: ptr int) {.noinline.} =
  p[] = p[] + 1

proc leafFlip*(p: ptr bool) {.noinline.} =
  p[] = not p[]

proc leafAbort*(code: int) {.noinline, noreturn.} =
  quit(code)
