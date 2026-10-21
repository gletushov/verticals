@main struct Checks {
 static func main() {
  var tap = FnTap()
  assert(!tap.flags(fn:true,other:false))
  assert(tap.flags(fn:false,other:false), "Fn alone must open after release")
  assert(!tap.flags(fn:false,other:false), "No duplicate on repeated flags")
  _ = tap.flags(fn:true,other:false); tap.key()
  assert(!tap.flags(fn:false,other:false), "Fn+key must not open")
  _ = tap.flags(fn:true,other:true)
  assert(!tap.flags(fn:false,other:false), "Fn with another modifier must not open")
  _ = tap.flags(fn:true,other:false); _ = tap.flags(fn:true,other:true)
  _ = tap.flags(fn:true,other:false)
  assert(!tap.flags(fn:false,other:false), "Releasing modifier first still cancels")
  print("Fn gesture checks passed")
 }
}
