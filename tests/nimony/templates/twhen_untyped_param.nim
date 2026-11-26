# A `when` condition or `const` value built from a checked template's
# `untyped` parameter is decided by each expansion, and a name declared in
# the branches is visible after the `when`.

import std/syncio

template a2(x: untyped): string =
  when compiles(x + 1): "c" else: "nc"

template isInt(x: untyped): bool =
  const tmp = typeof(x) is int
  tmp

template isDeclared(x: untyped): string =
  when declared(x): "declared" else: "undeclared"

template plusOne(x: untyped) =
  when compiles(x + 1):
    let r = x + 1
  else:
    let r = 0
  echo r

var gg = 1
echo a2(1), " ", a2("s")
echo isInt(1), " ", isInt("s")
echo isDeclared(gg), " ", isDeclared(nope)
plusOne(1)
plusOne("s")
