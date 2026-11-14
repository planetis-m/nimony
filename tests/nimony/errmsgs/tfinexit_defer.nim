# A proc-level `defer` is a `finally` around the rest of the proc: it runs
# after the `return` it encloses, so the `.ensures` a caller relies on is
# judged without what the `defer` may write.

{.feature: "staticContracts".}

proc f(): int {.ensures: result >= 0 and result < 8.} =
  defer: result = 1000000000
  result = 1

proc main =
  let k = f()
  {.assert: k < 8.}             # rests on the `.ensures` of `f`
  discard k

main()
