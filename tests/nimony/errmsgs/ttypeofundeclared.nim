# `typeof(e)` keeps the error of an operand that fails to type-check. A module-level
# `const`/`when` is checked before a toplevel `var`'s type is inferred.

type Inner = object
  a: int
var i = Inner(a: 4)
const c1 = typeof(i) is Inner
when typeof(i) is Inner:
  discard

proc p =
  discard typeof(undeclaredName) is int
  var x: typeof(undeclaredName)
