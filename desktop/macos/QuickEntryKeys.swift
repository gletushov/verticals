// A tap is decided at release, so Fn used as a modifier never opens Quick Entry.
struct FnTap {
    private var down = false
    private var cancelled = false
    mutating func flags(fn: Bool, other: Bool) -> Bool {
        if fn {
            if !down { cancelled = other }
            else if other { cancelled = true }
            down = true
            return false
        }
        let fire = down && !cancelled && !other
        down = false; cancelled = false
        return fire
    }
    mutating func key() { if down { cancelled = true } }
}
