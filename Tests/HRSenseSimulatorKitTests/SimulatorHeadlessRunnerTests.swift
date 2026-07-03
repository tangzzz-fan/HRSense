import XCTest
@testable import HRSenseSimulatorKit
import HRSenseProtocol

final class SimulatorHeadlessRunnerTests: XCTestCase {
    func test_remoteStartStreamStartsHeartRateAndWaveformPipelines() {
        let runner = SimulatorHeadlessRunner(
            launchOptions: SimulatorLaunchOptions(
                launchMode: .headless,
                autoStartAdvertising: false,
                autoStartStream: false
            ),
            output: { _ in }
        )
        let processor = runner.simulatedPeripheral.commandProcessor
        processor.didConnect()
        _ = processor.process(command: Command.hello(capabilities: Capabilities(rawValue: 0x01)), seq: 0)

        _ = processor.process(
            command: Command.startStream(sampleKinds: [DataKind.heartRate.rawValue, DataKind.waveform.rawValue]),
            seq: 1
        )

        XCTAssertTrue(runner.isStreaming)
        XCTAssertTrue(runner.isWaveformStreaming)
        runner.stopStreaming()
    }

    func test_remoteStopStreamStopsPipelines() {
        let runner = SimulatorHeadlessRunner(
            launchOptions: SimulatorLaunchOptions(
                launchMode: .headless,
                autoStartAdvertising: false,
                autoStartStream: false
            ),
            output: { _ in }
        )
        let processor = runner.simulatedPeripheral.commandProcessor
        processor.didConnect()
        _ = processor.process(command: Command.hello(capabilities: Capabilities(rawValue: 0x01)), seq: 0)
        _ = processor.process(command: Command.startStream(sampleKinds: [DataKind.heartRate.rawValue]), seq: 1)

        _ = processor.process(command: Command.stopStream(), seq: 2)

        XCTAssertFalse(runner.isStreaming)
        XCTAssertFalse(runner.isWaveformStreaming)
    }
}
