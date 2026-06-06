import Foundation

/// Bidirectional newline-delimited transport to the sidecar. Injectable for tests.
protocol SidecarTransport: AnyObject {
    var onLine: ((String) -> Void)? { get set }
    var onTerminate: (() -> Void)? { get set }
    func send(_ line: String)
    func start() throws
    func stop()
}

/// Launches the bundled Node sidecar and pipes stdio.
final class ProcessSidecarTransport: SidecarTransport {
    var onLine: ((String) -> Void)?
    var onTerminate: (() -> Void)?
    private let nodeURL: URL
    private let scriptURL: URL
    /// Mutable so the host can inject a freshly-fetched auth token before `start()`.
    var environment: [String: String]
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private var buffer = Data()

    init(nodeURL: URL, scriptURL: URL, environment: [String: String]) {
        self.nodeURL = nodeURL
        self.scriptURL = scriptURL
        self.environment = environment
    }

    func start() throws {
        process.executableURL = nodeURL
        process.arguments = [scriptURL.path]
        process.environment = environment
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            guard let self else { return }
            self.buffer.append(h.availableData)
            while let nl = self.buffer.firstIndex(of: 0x0A) {
                let lineData = self.buffer.subdata(in: self.buffer.startIndex..<nl)
                self.buffer.removeSubrange(self.buffer.startIndex...nl)
                if let line = String(data: lineData, encoding: .utf8) { self.onLine?(line) }
            }
        }
        process.terminationHandler = { [weak self] _ in self?.onTerminate?() }
        try process.run()
    }

    func send(_ line: String) {
        stdinPipe.fileHandleForWriting.write(Data(line.utf8))
    }

    func stop() {
        process.terminationHandler = nil
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }
}
