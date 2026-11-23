# Scalar replacement (SROA) of small fixed-size local arrays (N <= 8).
# Covers:
# - local array[4, int] written and read at literal indices (split)
# - same with one dynamic index (not split, still correct)
# - array whose address is taken (not split, still correct)
# - loop `for k in 0..3: acc[k] = acc[k] + x[k]` (splittable after complete unrolling)
# - float32 array, wrapper object holding an array, and nested 2x2 array.

import std / syncio

type
  Vec4Wrap = object
    v: array[4, float32]

  Mat2 = array[2, array[2, int]]

proc literalArray(x, y: int): int {.noinline.} =
  var a: array[4, int] = [1, 2, 3, 4]
  a[1] = x
  a[3] = a[0] + y
  result = a[0] + a[1] + a[2] + a[3]

proc dynamicIndexArray(x, idx: int): int {.noinline.} =
  var a: array[4, int] = [10, 20, 30, 40]
  a[2] = x
  result = a[0] + a[idx] + a[3]

proc bumpFirst(p: ptr int) {.noinline.} =
  p[] = p[] + 7

proc addrTakenArray(x: int): int {.noinline.} =
  var a: array[4, int] = [x, 2, 3, 4]
  bumpFirst(addr a[0])
  result = a[0] + a[1] + a[2] + a[3]

proc loopAccumArray(x: array[4, int]): int {.noinline.} =
  var acc: array[4, int] = [1, 2, 3, 4]
  for k in 0 .. 3:
    acc[k] = acc[k] + x[k]
  result = acc[0] + acc[1] * 2 + acc[2] * 3 + acc[3] * 4

proc floatArray(scale: float32): float32 {.noinline.} =
  var f: array[4, float32] = [1.5'f32, 2.5'f32, 3.5'f32, 4.5'f32]
  f[2] = f[0] * scale
  result = f[0] + f[1] + f[2] + f[3]

proc wrappedAndNested(x: int): int {.noinline.} =
  var w = Vec4Wrap()
  w.v[0] = 2.0'f32
  w.v[3] = 5.0'f32
  var m: Mat2 = [[x, 2], [3, 4]]
  m[1][0] = m[0][1] + 10
  result = int(w.v[0] + w.v[1] + w.v[3]) + m[0][0] + m[1][0] + m[1][1]

proc main() =
  echo literalArray(10, 20)
  echo dynamicIndexArray(5, 2), " ", dynamicIndexArray(5, 1)
  echo addrTakenArray(10)
  echo loopAccumArray([10, 20, 30, 40])
  echo int(floatArray(2.0'f32) * 10.0'f32)
  echo wrappedAndNested(6)

main()
