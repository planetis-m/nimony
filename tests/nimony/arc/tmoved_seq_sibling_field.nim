# A field DERIVED from a seq that a LATER field in the same object literal
# MOVES reads the moved-from (emptied) value:
#
#   WithSeq(flag: xs.len > 0, n: xs.len, items: xs)   # flag=false, n=5, items=5
#
# Compiles clean, no warning, no crash — just a wrong answer, and the wrong
# answer is the OPTIMISTIC one (a false `matched`/`isDegenerate` reads as
# "nothing found"), which is why it survives review.
#
# The duplifier turns the moving field into
# `(expr (stmts (cursor tmp = xs) (=wasMoved xs)) tmp)`; xelim then hoists
# those statements in front of the WHOLE constructor, so a sibling that reads
# `xs` runs after the move. The move itself is fine — only the `=wasMoved` has
# to wait, so the duplifier schedules it after the constructor rather than
# giving up the move and copying.
#
# TWO PROPERTIES THAT MAKE IT EASY TO MISS, both asserted below:
#
#   1. THE CORRUPTION IS SELECTIVE. Only the derived BOOL lies. The sibling
#      int reads 5 correctly and the moved seq arrives intact. Checking "did
#      the seq survive?" or "is the count right?" does NOT detect it.
#   2. IT IS SHAPE-DEPENDENT. Built from a PARAMETER the same literal is
#      correct; only the LOCAL-VAR form fails. A one-shape probe returns
#      "safe" and closes the investigation.
#
# Negative controls (both correct today) pin this to the MOVE rather than to
# boolean codegen in object literals: a bool from a comparison with no seq in
# the object, and a seq READ but not moved. Field order is irrelevant —
# derived-first and derived-last both fail.

import std / [syncio, assertions]

type
  WithSeq = object
    flag: bool
    n: int
    items: seq[int]

  NoSeq = object
    flag: bool
    n: int

proc fill(): seq[int] =
  result = @[]
  for i in 0 ..< 5:
    result.add i

proc fromParam(xs: seq[int]): WithSeq =
  # Shape control: the same literal built from a PARAMETER is correct.
  result = WithSeq(flag: xs.len > 0, n: xs.len, items: xs)

proc take(flag: bool; n: int; items: sink seq[int]): bool =
  result = flag and n == 5 and items.len == 5

proc main =
  # Control 1 — bool from a comparison, no seq in the object at all.
  let a = fill()
  let c1 = NoSeq(flag: a.len > 0, n: a.len)
  assert c1.flag

  # Control 2 — seq READ but not moved into the literal.
  let z = fill()
  let c2 = NoSeq(flag: z.len > 0, n: z.len)
  assert c2.flag

  # Hoisting the derived value to a local first.
  var ys = fill()
  let hoisted = ys.len > 0
  let c3 = WithSeq(flag: hoisted, n: 5, items: ys)
  assert c3.flag

  # Shape control — from a parameter, correct.
  assert fromParam(fill()).flag

  # THE BUG — derived from a local var that a later field moves.
  var xs = fill()
  let w = WithSeq(flag: xs.len > 0, n: xs.len, items: xs)
  assert w.n == 5            # sibling int is correct
  assert w.items.len == 5    # moved seq arrives intact
  assert w.flag              # used to read the moved-from value

  # Same hazard through a call's `sink` parameter rather than a constructor.
  var vs = fill()
  assert take(vs.len > 0, vs.len, vs)

  # And through a tuple constructor.
  var ts = fill()
  let tup = (ts.len > 0, ts.len, ts)
  assert tup[0]
  assert tup[2].len == 5

  # Derived field LAST rather than first.
  var us = fill()
  let w2 = WithSeq(items: us, n: 5, flag: us.len > 0)
  assert w2.flag

  echo "ok"

main()

# A sibling that reads the location through a borrow: `xelim` hoists the
# `lent` call (or an `openArray` view) into a temp, and the temp is read after
# the sibling that moves the location (#47 of nimony-bugs-fuzzers).
type
  Probe = object
    id: int
  ProbePair = object
    a, b: Probe

var live: array[16, bool]
var probes = 0

proc `=destroy`(x: Probe) =
  if x.id != 0:
    assert live[x.id]
    live[x.id] = false
proc `=wasMoved`(x: var Probe) = x.id = 0
proc `=dup`(x: Probe): Probe {.nodestroy.} =
  assert live[x.id]          # never a copy of a moved or destroyed value
  inc probes
  live[probes] = true
  result = Probe(id: probes)

proc probe(): Probe =
  inc probes
  live[probes] = true
  result = Probe(id: probes)

proc borrowP(x: var Probe): lent Probe = x
proc firstP(p: var ProbePair): lent Probe = p.a
proc dropP(x: sink Probe): int = 7
proc dropPs(s: sink seq[Probe]): int = s.len
proc liveCount(a: openArray[Probe]; n: int): int =
  result = n
  for x in a:
    if live[x.id]: inc result

proc borrowedSibling =
  var x = probe()
  let t = (borrowP(x), dropP(x))     # the borrow copied after the move
  assert t[1] == 7
  var p = ProbePair(a: probe(), b: probe())
  let q = (p.a, firstP(p))           # the move before the borrow's copy
  assert q[0].id != q[1].id
  var s = @[probe(), probe()]
  assert liveCount(toOpenArray(s, 0, 1), dropPs(s)) == 4

borrowedSibling()

{.feature: "assumeSync".}  # test program: globals shared freely
