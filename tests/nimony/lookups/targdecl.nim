## A declaration inside a call argument is checked once and is local to the
## argument: the same name may be declared again in a later argument, and a
## name declared before the call stays usable after it.

import std / syncio

proc f(x: int): int = x
template t(v: untyped): untyped = v
type E = enum A, B
var arr = [10, 20, 30]

echo arr[(let i = 1; i)], " ", arr[(let i = 2; i)]
echo $(let e = B; e), " ", $(let e = A; e)
echo t(f((let a = 1; a))), " ", t(f((let a = 2; a)))
echo static(f((let s = 1; s)) + 1), " ", static(f((let s = 2; s)) + 1)

proc p(): int =
  result = [7, 8][(let k = 1; k)]
  result += [7, 8][(let k = 0; k)]
echo p()

# the valid neighbour: declare before the call, then use it after
let i = 1
echo arr[i], " ", i
let e = B
echo $e, " ", e

# a declaration in the second operand of `and`, used inside the operand
let n = 3
if n > 0 and (let m = n * 2; m > 4):
  echo "big"
