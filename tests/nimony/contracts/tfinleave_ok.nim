# The proven side of `errmsgs/tfinexit_break`, `tfinexit_ensures` and
# `tfinexit_defer`: an exit through a `finally` keeps every fact about what
# the `finally` does not write, and each `return` is judged on its own.

{.feature: "staticContracts".}

import std/syncio

proc risky(x: int) {.raises.} =
  if x > 3: raise Failure

proc breakKeeps(): int =
  var i = 0
  block b:
    try:
      i = 7
      break b
    finally:
      echo "finally"
  {.assert: i == 7.}
  result = i

proc returnValue(): int {.ensures: result == 7.} =
  try:
    return 7
  finally:
    echo "finally"

proc deferKeeps(): int {.ensures: result == 3.} =
  var log = 0
  defer: log = 1
  result = 3

proc nested(): int {.ensures: result == 4.} =
  var y = 0
  try:
    try:
      result = 4
      return
    finally:
      y = 1
  finally:
    y = 2

proc eachReturn(x: int): int {.ensures: result == 1 or result == 2.} =
  try:
    risky(x)
    return 1
  except:
    return 2
  finally:
    echo "finally"

echo breakKeeps()
echo returnValue()
echo deferKeeps()
echo nested()
echo eachReturn(1)
echo eachReturn(9)
