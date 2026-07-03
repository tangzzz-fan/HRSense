/// TLV tag constants for L4 application data fields.
///
/// Defined in v1 protocol contract (doc 03 §6.2).
///
/// General tags (0x01–0x0F):
///   0x01 timestamp     — u32, device-relative ms
///   0x02 heartRate     — u8/u16, bpm
///   0x03 rrIntervals   — u16[], ms
///   0x04 battery       — u8, %
///   0x05 sensorStatus  — u8, bitmask
///   0x06 sampleSeq     — u32, sample sequence number
///   0x07 capabilities  — u32, capability bitmask (also used in L3 HELLO_ACK)
///
/// Waveform tags (0x10–0x15): see spec 0003 §3.1
public enum TLVTag: UInt8, Equatable, Sendable, CaseIterable {
    case timestamp   = 0x01
    case heartRate   = 0x02
    case rrIntervals = 0x03
    case battery     = 0x04
    case sensorStatus = 0x05
    case sampleSeq   = 0x06
    case capabilities = 0x07

    // Waveform (spec 0003 §3.1)
    case waveformType   = 0x10
    case sampleRate     = 0x11
    case blockSeq       = 0x12
    case startTimestamp = 0x13
    case sampleBits     = 0x14
    case samples        = 0x15
}
