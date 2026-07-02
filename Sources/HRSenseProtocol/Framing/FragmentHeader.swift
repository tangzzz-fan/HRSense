/// Fragment header bitfield (1 byte).
///
/// Layout:
///   bit7     — START (first fragment of a frame)
///   bit6     — END   (last fragment of a frame; START=END=1 means single-fragment frame)
///   bit5..0  — FRAG_IDX (incrementing fragment index within a frame)
public struct FragmentHeader: Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public init(start: Bool, end: Bool, fragIndex: UInt8) {
        var val: UInt8 = 0
        if start { val |= 0x80 }
        if end   { val |= 0x40 }
        val |= (fragIndex & 0x3F)
        self.rawValue = val
    }

    /// Whether this fragment marks the start of a frame.
    public var isStart: Bool { (rawValue & 0x80) != 0 }

    /// Whether this fragment marks the end of a frame.
    public var isEnd: Bool { (rawValue & 0x40) != 0 }

    /// Fragment index within the frame (0–63).
    public var fragIndex: UInt8 { rawValue & 0x3F }

    /// True if this is a single-fragment frame (START=END=1).
    public var isSingleFragment: Bool { isStart && isEnd }
}
