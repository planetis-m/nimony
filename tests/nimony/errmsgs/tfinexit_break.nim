# A `break` that leaves a `try` runs its `finally` on the way out: what the
# `finally` writes is not what the `try` body wrote before the `break`.

proc f(): int =
  var i = 0
  block b:
    try:
      i = 0
      break b
    finally:
      i = 100
  {.assert: i == 0.}            # false: `i` is 100 here
  result = i

discard f()
