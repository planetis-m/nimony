# A `when` condition or `const` value built from a checked template's
# `untyped` parameter has no value at the definition: each expansion
# decides it with the argument in place.

import std/syncio

template k7(x: untyped): string =
  when compiles(x): "c" else: "nc"

template a2(x: untyped): string =
  when compiles(x + 1): "c" else: "nc"

template kind(x: untyped): string =
  when compiles(x + 1): "num"
  elif compiles(x & "a"): "str"
  else: "other"

template addOne(x: untyped) =
  when compiles(x + 1):
    echo "add ", x + 1
  else:
    echo "noadd"

template isInt(x: untyped): bool =
  const tmp = typeof(x) is int
  tmp

template isDeclared(x: untyped): string =
  when declared(x): "declared" else: "undeclared"

# not built from a parameter: still decided at the definition, so a name
# declared in the taken branch is visible after the `when`
const K = true
template viaConst(x: untyped): int =
  when K:
    let y = 1
  else:
    let y = 2
  y + x

var gg = 1
echo k7(1)
echo a2(1), " ", a2("s")
echo kind(1), " ", kind("s"), " ", kind(true)
addOne(1)
addOne("s")
echo isInt(1), " ", isInt("s")
echo isDeclared(gg), " ", isDeclared(nope)
echo viaConst(10)
