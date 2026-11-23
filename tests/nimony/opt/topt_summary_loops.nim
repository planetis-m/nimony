# Regression test for summary-driven call handling in `unswitch` and
# `induction_variables`:
# - read-only / noreturn callees allow unswitching (on globals / addr-taken
#   locals) and strength reduction (count-to-zero and pointer-walk);
# - writing callees (mutating an addr-taken flag, writing a global, or growing
#   a `var seq`) still block them.

import std/syncio

var gFlag = true

proc roMix(x: int): int {.noinline.} =
  result = (x * 3) xor (x + 7)

proc roReadBool(p: ptr bool): int {.noinline.} =
  result = if p[]: 1 else: 0

proc flipFlag(p: ptr bool) {.noinline.} =
  p[] = not p[]

proc flipGlobal() {.noinline.} =
  {.cast(assumeSync).}:
    gFlag = not gFlag

proc growSeq(s: var seq[int]; v: int) {.noinline.} =
  s.add v

proc unswitchRoGlobal(n: int): int {.noinline.} =
  var i = 0
  result = 0
  while i < n:
    let m = roMix(i)
    {.cast(assumeSync).}:
      if gFlag: result += m
      else: result -= m
      if gFlag: result += 1
      else: result -= 1
    inc i

proc unswitchRoAddrTaken(initFlag: bool; n: int): int {.noinline.} =
  var flag = initFlag
  let p = addr flag
  var i = 0
  result = 0
  while i < n:
    let m = roReadBool(p)
    if flag: result += m + 2
    else: result -= m + 2
    if flag: result += 1
    else: result -= 1
    inc i

proc unswitchWritingPtr(n: int): int {.noinline.} =
  var flag = true
  let p = addr flag
  var i = 0
  result = 0
  while i < n:
    if flag: result += 10
    else: result += 1
    if flag: result += 20
    else: result += 2
    flipFlag(p)
    inc i

proc unswitchWritingGlobal(n: int): int {.noinline.} =
  {.cast(assumeSync).}:
    gFlag = true
  var i = 0
  result = 0
  while i < n:
    {.cast(assumeSync).}:
      if gFlag: result += 10
      else: result += 1
      if gFlag: result += 20
      else: result += 2
    flipGlobal()
    inc i

proc ivPtrReadOnly(p: ptr UncheckedArray[int]; n: int): int {.noinline.} =
  result = 0
  var i = 0
  while i < n:
    result += roMix(p[i])
    inc i

proc ivSeqReadOnly(s: var seq[int]): int {.noinline.} =
  result = 0
  var i = 0
  let n = s.len
  while i < n:
    result += roMix(s[i])
    inc i

proc ivSeqGrowing(s: var seq[int]): int {.noinline.} =
  result = 0
  var i = 0
  let n = s.len
  while i < n:
    let v = s[i]
    result += v
    growSeq(s, v + 100)
    inc i

proc main() =
  {.cast(assumeSync).}:
    gFlag = true
  echo unswitchRoGlobal(6)
  {.cast(assumeSync).}:
    gFlag = false
  echo unswitchRoGlobal(6)
  echo unswitchRoAddrTaken(true, 4), " ", unswitchRoAddrTaken(false, 4)
  echo unswitchWritingPtr(4)
  echo unswitchWritingGlobal(4)
  var a = @[1, 2, 3, 4, 5]
  echo ivPtrReadOnly(cast[ptr UncheckedArray[int]](addr a[0]), a.len)
  echo ivSeqReadOnly(a)
  var b = @[1, 2, 3, 4]
  echo ivSeqGrowing(b), " ", b.len

main()
