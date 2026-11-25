
import std / [syncio]

proc myecho(x: int = 4) =
  echo x

myecho()

# a default that calls a proc literal: the call site checks the typed
# `(expr (stmts (proc ...)) anonproc)` callee again
proc addLit(a: int; w = (proc (): int = 3)()): int = a + w
echo addLit(1)

# a default that reads an earlier parameter sees the caller's argument,
# evaluated once
proc p(a: int; w = a): int = w
proc chain(a: int; w = a + 1; z = w * 2): int = a + w + z
proc gen[T](a: T; w = a): T = w
proc bump(a: var int; w = a): int =
  inc a
  result = w
proc count(a: openArray[int]; n = a.len): int = n
proc next(c: var int): int =
  inc c
  result = c

proc main =
  var calls = 0
  echo p(4), " ", p(a = 5), " ", p(next(calls)), " ", calls
  echo chain(next(calls)), " ", calls
  echo gen("x"), " ", gen(next(calls)), " ", calls
  var arr = [10, 20, 30]
  echo bump(arr[next(calls) - 3]), " ", arr[1], " ", calls
  var s = @[1, 2]
  echo count(s), " ", count([7, 8, 9])
  s.add 3 # `s` is not left borrowed by the call
  echo count(s)
main()
