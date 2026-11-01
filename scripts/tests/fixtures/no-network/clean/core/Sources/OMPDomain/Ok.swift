import Foundation
// URLSession is never used; this comment must not trip the lint.
/// Loads bundled JSON from disk, never from the network (no NWConnection either).
public let seedURL = URL(fileURLWithPath: "/tmp/seed.json")
public let localData = try? Data(contentsOf: seedURL)
