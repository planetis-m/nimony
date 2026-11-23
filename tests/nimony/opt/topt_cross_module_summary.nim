# Cross-module summary resolution regression test:
# `midRo` lives in another module and calls a third module (`leafHash` +
# `noreturn` `leafAbort`), so its intra-module `.c.nif` summary has
# `callsUnknown`. `shoggoth opt` resolves it transitively so CSE, unswitch, and
# induction_variables fire across `midRo`, while cross-module writing callees
# (`midBump`, `midFlip`) still block CSE and unswitching.

import std/syncio
import deps/mcrosssummary_mid

var gCrossFlag = true

proc cseAcrossCrossModRo(p: ptr int; x: int): int {.noinline.} =
  let a = p[]
  let m = midRo(x)
  let b = p[]
  result = a + b + m

proc cseBlockedByCrossModWrite(p: ptr int): int {.noinline.} =
  let a = p[]
  midBump(p)
  let b = p[]
  result = a * 10 + b

proc unswitchCrossModRo(n: int): int {.noinline.} =
  var i = 0
  result = 0
  while i < n:
    let m = midRo(i)
    {.cast(assumeSync).}:
      if gCrossFlag: result += m
      else: result -= m
      if gCrossFlag: result += 1
      else: result -= 1
    inc i

proc unswitchBlockedByCrossModWrite(n: int): int {.noinline.} =
  var flag = true
  let p = addr flag
  var i = 0
  result = 0
  while i < n:
    if flag: result += 10
    else: result += 1
    if flag: result += 20
    else: result += 2
    midFlip(p)
    inc i

proc ivCrossModRo(p: ptr UncheckedArray[int]; n: int): int {.noinline.} =
  result = 0
  var i = 0
  while i < n:
    result += midRo(p[i])
    inc i

proc main() =
  var v = 7
  echo cseAcrossCrossModRo(addr v, 3)
  echo cseBlockedByCrossModWrite(addr v)
  {.cast(assumeSync).}:
    gCrossFlag = true
  echo unswitchCrossModRo(5)
  {.cast(assumeSync).}:
    gCrossFlag = false
  echo unswitchCrossModRo(5)
  echo unswitchBlockedByCrossModWrite(4)
  var a = @[1, 2, 3, 4]
  echo ivCrossModRo(cast[ptr UncheckedArray[int]](addr a[0]), a.len)

main()
