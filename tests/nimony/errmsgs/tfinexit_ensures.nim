# A `return` runs the `finally` it leaves through before the routine is left,
# so its `.ensures` is judged without what the `finally` may write.

{.feature: "staticContracts".}

proc g(): int {.ensures: result == 0.} =
  try:
    result = 0
    return
  finally:
    result = 100                # `g` returns 100

discard g()
