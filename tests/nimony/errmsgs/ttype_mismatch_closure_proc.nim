proc dontTakeClosure(p: proc ()) = discard

proc test =
  proc closureProc() {.closure.} = discard
  dontTakeClosure(closureProc)

test()

proc takesOpenArray(a: openArray[int]; b: int) = discard
takesOpenArray([1, 2], 3, 4)

# a nimcall routine converts to a closure only as a whole argument, not as a
# field of a tuple argument:
type Setup = proc (x: int): int {.closure.}
proc dbl(x: int): int = x * 2
proc put[T](s: var seq[T]; x: sink T) = discard
var cases: seq[(string, Setup)] = @[]
put(cases, ("b", dbl))
