when defined(nimony):
  {.feature: "assumeSync".}
import mroutineglobala

proc fromB*(): int =
  var counter {.global.}: int
  inc counter
  counter

proc b1*(): int = counted(10)

let sharedAtB* = shared(1) # the initializer ran before this module's toplevel
proc b2*(): int = shared(2)
proc b3*(): int =
  result = 0
  for v in sharedItems(2): result = v
let kindsAtB* = sharedKinds(1)
proc b4*(): string = sharedKinds(2)
