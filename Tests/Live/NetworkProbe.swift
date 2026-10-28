import SwiftUI
import Network

/// A separate, ad-hoc signed app for real flow attribution and allow/block tests.
/// It sends public HTTP and STUN requests. It never changes policy.
@main
struct NetworkProbeApp: App {
    @StateObject private var probe = NetworkProbe()
    var body: some Scene {
        WindowGroup("OpenFirewall Network Probe") {
            VStack(alignment: .leading, spacing: 18) {
                Text("OpenFirewall Network Probe").font(.title2.bold())
                Text("A separate test app for TCP and UDP rules.").foregroundStyle(.secondary)
                HStack {
                    Button("Test TCP") { probe.run(udp: false) }
                    Button("Test UDP") { probe.run(udp: true) }
                    Button("Hold TCP open") { probe.run(udp: false, hold: true) }
                    Button("Stop test") { probe.stop() }
                }
                Text(probe.status).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                Text("TCP: example.com:80. UDP: stun.cloudflare.com:3478.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Fresh connections. Normal tests: 10 seconds. Held connection: 120 seconds.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(28).frame(width: 560, height: 240)
        }
    }
}

@MainActor
final class NetworkProbe: ObservableObject {
    @Published var status = "Ready. No request sent yet."
    private var connection: NWConnection?
    private var timeout: Task<Void, Never>?
    private var attemptID = UUID()
    private var startedAt = Date()
    private var resultSuffix = ""

    func stop() { connection?.cancel(); connection = nil; timeout?.cancel(); timeout = nil; attemptID = UUID(); status = "Stopped." }
    func run(udp: Bool, hold: Bool = false) {
        stop(); startedAt = Date()
        resultSuffix = hold ? "tcp-hold" : udp ? "udp" : "tcp"
        let id = attemptID
        let transport = udp ? "UDP" : "TCP"
        let host = udp ? "stun.cloudflare.com" : "example.com"
        let port = udp ? UInt16(3478) : UInt16(80)
        status = "\(transport): connecting to \(host):\(port)…"
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: udp ? .udp : .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.attemptID == id else { return }
                switch state {
                case .ready:
                    var message = Data("GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n".utf8)
                    if hold {
                        // Incomplete request headers hold a real TCP socket open without a response.
                        message = Data("GET / HTTP/1.1\r\nHost: example.com\r\n".utf8)
                        self.status = "TCP OPEN: waiting on a held connection. Apply Block to this app now."
                        self.save(ProbeResult(attempt: id, startedAt: self.startedAt, completedAt: Date(),
                            transport: transport, success: true, detail: "TCP connection established and held open."), suffix: "hold-ready")
                    }
                    if udp {
                        // STUN binding request, no attributes. No mapped address is saved.
                        message = Data([0, 1, 0, 0, 0x21, 0x12, 0xa4, 0x42,
                                        0x4f, 0x46, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
                    }
                    connection.send(content: message, completion: .contentProcessed { error in
                        if let error { Task { @MainActor in self.finish(id, transport: transport, success: false, detail: error.localizedDescription) } }
                    })
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
                        Task { @MainActor in
                            guard self.attemptID == id else { return }
                            let data = data ?? Data()
                            let valid = udp ? data.count >= 20 && data.prefix(2) == Data([1, 1]) &&
                                data[4..<20] == Data([0x21, 0x12, 0xa4, 0x42, 0x4f, 0x46, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
                                : String(decoding: data, as: UTF8.self).hasPrefix("HTTP/")
                            self.finish(id, transport: transport, success: valid,
                                detail: valid ? "Received \(data.count) response bytes." : error?.localizedDescription ?? "No valid response received.")
                        }
                    }
                case .failed(let error): self.finish(id, transport: transport, success: false, detail: error.localizedDescription)
                default: break
                }
            }
        }
        connection.start(queue: .global())
        timeout = Task { [weak self] in
            let seconds = hold ? 120 : 10
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finish(id, transport: transport, success: false, detail: "Timed out after \(seconds) seconds.")
        }
    }

    private func finish(_ id: UUID, transport: String, success: Bool, detail: String) {
        guard attemptID == id, connection != nil else { return }
        timeout?.cancel(); timeout = nil; connection?.cancel(); connection = nil
        status = "\(transport) \(success ? "SUCCEEDED" : "FAILED"): \(detail)"
        let result = ProbeResult(attempt: id, startedAt: startedAt, completedAt: Date(), transport: transport, success: success, detail: detail)
        save(result, suffix: resultSuffix)
    }
    private func save(_ result: ProbeResult, suffix: String) {
        let directory = Bundle.main.bundleURL.deletingLastPathComponent()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(result).write(to: directory.appendingPathComponent("probe-result-\(suffix).json"), options: .atomic)
        } catch { status += " Could not save result: \(error.localizedDescription)" }
    }
}

struct ProbeResult: Codable {
    let attempt: UUID
    let startedAt: Date
    let completedAt: Date
    let transport: String
    let success: Bool
    let detail: String
}
