# An operand of `typeof` that does not type-check is reported at the operand,
# in every position a `typeof` can appear.
import std/syncio

var a: typeof(zzz1)
var b: typeof(1 + zzz2)
var c: typeof(zzz3, typeOfProc)

type
  O = object
    f: typeof(zzz4)

proc p(x: typeof(zzz5)) = discard

proc r() =
  var l: typeof(zzz7)

proc g[T](x: T) =
  var l: typeof(zzz8)

g(1)

var d = default(typeof(zzz9))
