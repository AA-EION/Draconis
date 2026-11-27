import Foundation

/// The VR mod captures the game's own audio through the virtual device
/// "VAD\Process_Loopback". Wine's mmdevapi doesn't know that device, the call
/// fails and the mod fast-fails with 0xC0000409. The fix (from MWGIH's
/// TF2SteamFrame, GPL-3.0) points the one instruction that loads that string
/// at the DEVINTERFACE_AUDIO_RENDER GUID, which Wine maps to the default output
/// device. Only the installed copy of the mod's DLL is changed.
public enum LoopbackPatch {
    public enum State: Equatable, Sendable { case patched, unpatched, unknown(String) }

    static let loopback = utf16z(#"VAD\Process_Loopback"#)
    static let render = utf16z("{E6327CAD-DCEC-4949-AE8A-991E976A79D2}")
    static let code: UInt32 = 0x20, execute: UInt32 = 0x2000_0000, writable: UInt32 = 0x8000_0000

    static func utf16z(_ s: String) -> [UInt8] {
        (s + "\0").utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
    }

    struct Section {
        var header: Int, va: Int, vsize: Int, rptr: Int, rsize: Int, flags: UInt32
        var isCode: Bool { flags & (LoopbackPatch.code | LoopbackPatch.execute) != 0 }
    }

    static func u16(_ d: [UInt8], _ o: Int) -> Int { Int(d[o]) | Int(d[o + 1]) << 8 }
    public static func u32(_ d: [UInt8], _ o: Int) -> UInt32 {
        UInt32(d[o]) | UInt32(d[o + 1]) << 8 | UInt32(d[o + 2]) << 16 | UInt32(d[o + 3]) << 24
    }
    static func i32(_ d: [UInt8], _ o: Int) -> Int { Int(Int32(bitPattern: u32(d, o))) }
    static func put32(_ d: inout [UInt8], _ o: Int, _ v: UInt32) {
        for i in 0..<4 { d[o + i] = UInt8((v >> (8 * UInt32(i))) & 0xFF) }
    }

    static func sections(_ d: [UInt8]) -> [Section]? {
        guard d.count > 0x40, d[0] == 0x4D, d[1] == 0x5A else { return nil }
        let pe = Int(u32(d, 0x3C))
        guard pe + 24 <= d.count, Array(d[pe..<pe + 4]) == [0x50, 0x45, 0, 0] else { return nil }
        let count = u16(d, pe + 6), optSize = u16(d, pe + 20)
        return (0..<count).compactMap { i in
            let o = pe + 24 + optSize + 40 * i
            guard o + 40 <= d.count else { return nil }
            return Section(header: o, va: Int(u32(d, o + 12)), vsize: Int(u32(d, o + 8)),
                           rptr: Int(u32(d, o + 20)), rsize: Int(u32(d, o + 16)), flags: u32(d, o + 36))
        }
    }

    static func rva(_ sections: [Section], offset: Int) -> Int? {
        sections.first { $0.rptr <= offset && offset < $0.rptr + $0.rsize }.map { $0.va + offset - $0.rptr }
    }

    public static func find(_ d: [UInt8], _ needle: [UInt8], from start: Int) -> Int? {
        guard needle.count <= d.count, start <= d.count - needle.count else { return nil }
        var i = start
        while i <= d.count - needle.count {
            if d[i] == needle[0], Array(d[i..<i + needle.count]) == needle { return i }
            i += 1
        }
        return nil
    }

    /// File offsets of `lea r64, [rip+disp32]` in code sections that load `target`.
    static func leaRefs(_ d: [UInt8], _ sections: [Section], target: Int) -> [Int] {
        var hits: [Int] = []
        for s in sections where s.isCode {
            let end = min(s.rptr + s.rsize, d.count) - 7
            var i = s.rptr
            while i < end {
                if (d[i] == 0x48 || d[i] == 0x4C), d[i + 1] == 0x8D, (d[i + 2] & 0xC7) == 0x05,
                   s.va + (i - s.rptr) + 7 + i32(d, i + 3) == target {
                    hits.append(i)
                }
                i += 1
            }
        }
        return hits
    }

    static func state(_ d: [UInt8]) -> (State, ref: Int?) {
        guard let sections = sections(d) else { return (.unknown("not a PE file"), nil) }
        var found: [(Bool, Int)] = []
        for (needle, patched) in [(loopback, false), (render, true)] {
            var pos = find(d, needle, from: 0)
            while let p = pos {
                if let r = rva(sections, offset: p) {
                    found += leaRefs(d, sections, target: r).map { (patched, $0) }
                }
                pos = find(d, needle, from: p + 2)
            }
        }
        if found.count == 1 { return (found[0].0 ? .patched : .unpatched, found[0].1) }
        if found.isEmpty { return (.unknown("no instruction loads the loopback device path"), nil) }
        return (.unknown("\(found.count) instructions load the device path; expected one"), nil)
    }

    public static func check(_ dll: URL) -> State {
        guard let data = try? Data(contentsOf: dll) else { return .unknown("unreadable") }
        return state([UInt8](data)).0
    }

    /// Patch in place; returns `.patched` when done (or already done).
    @discardableResult
    public static func apply(to dll: URL) throws -> State {
        var d = [UInt8](try Data(contentsOf: dll))
        let (current, ref) = state(d)
        guard current == .unpatched, let ref, let sections = sections(d), let leaRVA = rva(sections, offset: ref)
        else { return current }
        // The GUID string goes in the unused tail of a read-only data section,
        // whose VirtualSize then grows to cover it.
        let ordered = sections.sorted { $0.va < $1.va }
        var done = false
        for (index, s) in ordered.enumerated() where !s.isCode && s.rsize > 0 && s.flags & writable == 0 {
            let start = (s.vsize + 15) & ~15, end = start + render.count
            let nextVA = index + 1 < ordered.count ? ordered[index + 1].va : nil
            guard end <= s.rsize, nextVA.map({ s.va + end <= $0 }) ?? true,
                  d[(s.rptr + start)..<(s.rptr + end)].allSatisfy({ $0 == 0 }) else { continue }
            d.replaceSubrange((s.rptr + start)..<(s.rptr + end), with: render)
            put32(&d, s.header + 8, UInt32(end))
            put32(&d, ref + 3, UInt32(bitPattern: Int32(s.va + start - (leaRVA + 7))))
            done = true
            break
        }
        guard done else { return .unknown("no room in the DLL for the device path") }
        let after = state(d).0
        guard after == .patched else { return .unknown("the patch didn't verify") }
        try Data(d).write(to: dll, options: .atomic)
        return .patched
    }
}
