# End-to-end regression test for Shoggoth's scalar loop unroller (`unroll.nim`).
# Covers:
# - trip counts 0, 1, factor-1, factor, factor+1, and large counts across
#   `<` (count-to-zero & value-using), `<=`, `countdown`, factor-2 medium body
# - small constant-trip full unrolling (0, 1, 3, 4, 8) and exact-divisible 32
# - early exit (`break`) on both full- and partial-unrolled loops (checking `iv`)
# - locals declared in the loop body (incl. field shadowing + inner branches)
# - loops that must NOT be unrolled (returning call, large body, outer loop)

import std/syncio

type
  Rec = object
    t: int
    v: int

proc bump(x: int; cnt: var int): int {.noinline.} =
  inc cnt
  result = x * 3 + 1

# 1. Dynamic CountUpExclusive — count-to-zero (index-only) -> 4x with literal limit -3
proc sumC2z(a: ptr UncheckedArray[int]; n: int): int {.noinline.} =
  result = 0
  for i in 0 ..< n:
    result += a[i]

# 2. Dynamic CountUpExclusive — counter used as value -> 4x dynamic stop
proc sumVal(n: int): int {.noinline.} =
  result = 0
  for i in 0 ..< n:
    result += i * 3 + 1

# 3. Dynamic CountUp (`<=`) -> 4x
proc sumIncl(n: int): int {.noinline.} =
  result = 0
  var i = 0
  while i <= n:
    result += i + 2
    inc i

# 4. Dynamic CountDown (`countdown`) -> 4x with literal limit 3
proc sumDown(n: int): int {.noinline.} =
  result = 0
  var i = n
  while i >= 0:
    result = result * 31 + i + 1
    dec i

# 5. Medium body -> factor 2 (too big for 4x, fits 2x)
proc sumMed(a, b: ptr UncheckedArray[int]; n: int): int {.noinline.} =
  result = 0
  for i in 0 ..< n:
    let x = a[i]
    let y = b[i]
    result = result xor (x xor y) xor (x and y)

# 6. Small constant-trip loops (0, 1, 3, 4, 8) -> full unroll
proc fullConst(seed: int): int {.noinline.} =
  var a = default(array[8, int])
  for i in 0 ..< 8:
    a[i] = seed + i * 5
  var s = 0
  var z = 0
  while z < 0:
    s += 999
    inc z
  for i in 0 ..< 1:
    s += a[i] * 2
  for i in 0 ..< 3:
    s += a[i]
  for i in 0 ..< 4:
    s += a[i + 4]
  result = s

# 7. Exact-divisible constant trip (32) -> 4x with zero remainder
proc xor32(a, b: array[32, uint8]): int {.noinline.} =
  var c = default(array[32, uint8])
  for i in 0 ..< 32:
    c[i] = a[i] xor b[i]
  result = 0
  for i in 0 ..< 32:
    result += int(c[i])

# 8. Early exit (`break`) — dynamic partial unroll & constant full unroll
proc findDyn(a: ptr UncheckedArray[int]; n, target: int): int {.noinline.} =
  var found = -1
  var idx = 0
  while idx < n:
    if a[idx] == target:
      found = idx
      break
    inc idx
  result = found * 1000 + idx

proc findConst(a: array[6, int]; target: int): int {.noinline.} =
  var found = -1
  var idx = 0
  while idx < 6:
    if a[idx] == target:
      found = idx
      break
    inc idx
  result = found * 1000 + idx

# 9. Body declaring locals (shadowing a field name `t`) + internal branch
proc bodyLocals(r: Rec; n: int): int {.noinline.} =
  result = 0
  for i in 0 ..< n:
    var t = r.t xor i
    if (t and 1) == 0:
      t = t xor r.v
    result = result xor t

# 10. Loops that MUST NOT be unrolled: returning call, large body, outer loop
proc withCall(n: int; cnt: var int): int {.noinline.} =
  result = 0
  for i in 0 ..< n:
    result += bump(i, cnt)

proc largeBody(n: int): int {.noinline.} =
  result = 0
  for i in 0 ..< n:
    var x = i + 1
    x = (x * 3) xor (x + 7)
    x = (x * 5) xor (x + 11)
    x = (x * 7) xor (x + 13)
    x = (x * 11) xor (x + 17)
    x = (x * 13) xor (x + 19)
    x = (x * 17) xor (x + 23)
    x = (x * 19) xor (x + 29)
    x = (x * 23) xor (x + 31)
    result += x

proc nestedOuter(m, n: int): int {.noinline.} =
  result = 0
  for i in 0 ..< m:
    var row = 0
    for j in 0 ..< n:
      row += i * 10 + j
    result += row

# ---- Exercise every trip count: 0, 1, 2, 3, 4, 5, 13, 100 ------------------

var backingA = default(array[128, int])
var backingB = default(array[128, int])
for i in 0 ..< 128:
  backingA[i] = i * 7 + 3
  backingB[i] = i * 7 + 3
let ptrA = cast[ptr UncheckedArray[int]](addr backingA[0])
let ptrB = cast[ptr UncheckedArray[int]](addr backingB[0])

for n in [0, 1, 2, 3, 4, 5, 13, 100]:
  let c2z = sumC2z(ptrA, n)
  let val = sumVal(n)
  let incv = sumIncl(n - 1)
  let dnv = sumDown(n - 1)
  let med = sumMed(ptrA, ptrB, n)
  let loc = bodyLocals(Rec(t: 5, v: 3), n)
  echo n, ":", c2z, ",", val, ",", incv, ",", dnv, ",", med, ",", loc

echo "full:", fullConst(10)

var x1 = default(array[32, uint8])
var x2 = default(array[32, uint8])
for i in 0 ..< 32:
  x1[i] = uint8(i * 3 + 1)
  x2[i] = uint8(i * 5 + 7)
echo "xor32:", xor32(x1, x2)

for n in [0, 1, 3, 4, 5, 17]:
  echo "fd:", n, ":", findDyn(ptrA, n, 3), ",", findDyn(ptrA, n, 24), ",",
    findDyn(ptrA, n, 31), ",", findDyn(ptrA, n, 9999)

let ca: array[6, int] = [10, 20, 30, 40, 50, 60]
echo "fc:", findConst(ca, 10), ",", findConst(ca, 20), ",", findConst(ca, 40),
  ",", findConst(ca, 60), ",", findConst(ca, 99)

var callCount = 0
echo "nounroll:", withCall(7, callCount), ",", callCount, ",", largeBody(9), ",", nestedOuter(5, 6)
