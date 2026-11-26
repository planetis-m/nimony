# A subrange argument against its base type, or a base-type argument against a
# subrange, is a subrange match: it ranks below a generic match
# (doc/language.md, "Some Examples": `takesInt(z) # "T"`).
import std/syncio

proc p(x: int): string = "int"
proc p[T](x: T): string = "T"
proc ch(x: char): string = "char"
proc ch[T](x: T): string = "T"
proc v(x: var int): string = "var int"
proc v[T](x: var T): string = "var T"
proc g(x: int; y: int): string = "int,int"
proc g[T](x, y: T): string = "T,T"

var z: range[0..4] = 0
var nat: Natural = 3
var c: range['a'..'z'] = 'a'
var i = 1
echo p(z), " ", p(nat), " ", ch(c), " ", v(nat), " ", v(i)
echo g(nat, 1), " ", g(nat, i), " ", g(i, nat)
