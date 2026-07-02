import Foundation
import HRSenseProtocol

/// Processes incoming command frames and produces response frames.
///
/// Routes each command opcode to the appropriate handler:
///   HELLO → HELLO_ACK, GET_INFO → INFO, START_STREAM / STOP_STREAM / SET_CONFIG.
public final class CommandProcessor: @unchecked Sendable {

    public private(set) var state: DeviceState = .advertising
    private let config: SimulatorConfig
    private var onGeneratorStart: (() -> Void)?
    private var onGeneratorStop: (() -> Void)?
    private var streamSeq: UInt8 = 0

    public init(
        config: SimulatorConfig,
        onGeneratorStart: (() -> Void)? = nil,
        onGeneratorStop: (() -> Void)? = nil
    ) {
        self.config = config
        self.onGeneratorStart = onGeneratorStart
        self.onGeneratorStop = onGeneratorStop
    }

    /// Process a decoded Command from the App. Returns response fragments (if any).
    /// - Parameters:
    ///   - command: the decoded command.
    ///   - seq: frame sequence number (echoed in ACK).
    /// - Returns: array of response Data fragments (may be empty).
    public func process(command: Command, seq: UInt8) -> [Data] {
        let mtu = config.mtu

        switch command.opCode {
        case .hello:
            return handleHello(seq: seq, mtu: mtu)

        case .getInfo:
            return handleGetInfo(seq: seq, mtu: mtu)

        case .startStream:
            return handleStartStream(seq: seq, mtu: mtu)

        case .stopStream:
            return handleStopStream(seq: seq, mtu: mtu)

        case .setConfig:
            return handleSetConfig(seq: seq, mtu: mtu)

        case .error:
            // Error from App — log, no response
            return []

        default:
            // Unknown opcode — return ERROR via ACK
            return sendError(opcode: command.opCode.rawValue, reason: "Unknown command", seq: seq, mtu: mtu)
        }
    }

    /// Reset state (on disconnect).
    public func reset() {
        state = .advertising
        streamSeq = 0
    }

    /// Advance to connected state.
    public func didConnect() {
        if state == .advertising {
            state = .connected
        }
    }

    /// Handle disconnect.
    public func didDisconnect() {
        onGeneratorStop?()
        state = .advertising
    }

    /// Encode a data sample for the current stream.
    public func encodeSample(_ sample: DeviceSample) -> [Data] {
        let seq = streamSeq
        streamSeq = streamSeq &+ 1
        return encodeData(sample, seq: seq, mtu: config.mtu)
    }

    // MARK: - Private handlers

    private func handleHello(seq: UInt8, mtu: Int) -> [Data] {
        state = state.transition(on: .handshakeCompleted)
        let caps = HRSenseProtocol.Capabilities(rawValue: config.capabilities)
        let response = Command.helloAck(
            version: config.protocolVersion,
            capabilities: caps,
            model: config.model,
            firmwareVersion: config.firmwareVersion
        )
        return encodeCommand(response, seq: seq, mtu: mtu)
    }

    private func handleGetInfo(seq: UInt8, mtu: Int) -> [Data] {
        // Return a HELLO_ACK-style response as INFO
        let caps = HRSenseProtocol.Capabilities(rawValue: config.capabilities)
        let response = Command.helloAck(
            version: config.protocolVersion,
            capabilities: caps,
            model: config.model,
            firmwareVersion: config.firmwareVersion
        )
        return encodeCommand(response, seq: seq, mtu: mtu)
    }

    private func handleStartStream(seq: UInt8, mtu: Int) -> [Data] {
        state = state.transition(on: .streamStarted)
        onGeneratorStart?()
        // ACK the start
        let ack = ACKPayload(seq: seq, opcode: CommandOpCode.startStream.rawValue, status: 0x00)
        let fragments = encodeACK(ack, seq: seq, mtu: mtu)
        return fragments
    }

    private func handleStopStream(seq: UInt8, mtu: Int) -> [Data] {
        state = state.transition(on: .streamStopped)
        onGeneratorStop?()
        let ack = ACKPayload(seq: seq, opcode: CommandOpCode.stopStream.rawValue, status: 0x00)
        return encodeACK(ack, seq: seq, mtu: mtu)
    }

    private func handleSetConfig(seq: UInt8, mtu: Int) -> [Data] {
        let ack = ACKPayload(seq: seq, opcode: CommandOpCode.setConfig.rawValue, status: 0x00)
        return encodeACK(ack, seq: seq, mtu: mtu)
    }

    private func sendError(opcode: UInt8, reason: String, seq: UInt8, mtu: Int) -> [Data] {
        let ack = ACKPayload(seq: seq, opcode: opcode, status: 0x01)
        return encodeACK(ack, seq: seq, mtu: mtu)
    }
}
