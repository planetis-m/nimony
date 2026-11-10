## A declaration in a `typeof` operand is local to the operand: it is checked
## once, and two operands may declare the same name.

import std / syncio

type T = typeof((let a = 1; a))
var x: T
echo x

type
  A = typeof((let a = 1; a))
  B = typeof((let a = 'x'; a))
var y: A
var z: B
echo y, " ", ord(z)

proc p(v: typeof((let b = 1; b))): typeof((let b = 2; b + 1)) =
  var s: seq[typeof((let c = v; c))] = @[]
  s.add v
  result = s[0] + 1
echo p(1)

# a deferred toplevel local reached from a `typeof` in a `when` condition
let q: seq[int] = @[1, 2, 3]
when typeof(q) is seq[int]:
  echo "q-seq"
echo q.len
