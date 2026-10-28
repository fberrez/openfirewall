import Foundation
import Network

/// Isolated test app. Pair with loopback-echo.py. Never changes rules or proxies.
@main
struct LoopbackProbe {
    @MainActor static func main() async {
        let args = CommandLine.arguments
        guard args.count == 4, ["tcp", "udp"].contains(args[1]),
              ["127.0.0.1", "127.0.0.2", "::1"].contains(args[2]),
              let port = UInt16(args[3]), port > 0 else {
            fputs("Usage: LoopbackProbe tcp|udp 127.0.0.1|127.0.0.2|::1 PORT\n", stderr)
            exit(64)
        }
        let result = await EchoAttempt(host: args[2], port: port, udp: args[1] == "udp").run()
        let value: [String: Any] = ["success": result.0, "transport": args[1], "host": args[2], "port": port, "detail": result.1]
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        exit(result.0 ? 0 : 2)
    }
}

@MainActor
private final class EchoAttempt {
    let connection: NWConnection
    let udp: Bool
    let payload = Data("openfirewall-loopback-\(UUID().uuidString)".utf8)
    private var reply: CheckedContinuation<(Bool, String), Never>?
    private var timeout: Task<Void, Never>?
    init(host: String, port: UInt16, udp: Bool) {
        self.udp = udp
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: udp ? .udp : .tcp)
    }
    func run() async -> (Bool, String) {
        await withCheckedContinuation { continuation in
            reply = continuation
            connection.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready: self.send()
                    case .failed(let error): self.finish(false, error.localizedDescription)
                    default: break
                    }
                }
            }
            connection.start(queue: .global())
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                self?.finish(false, "Timed out")
            }
        }
    }
    private func send() {
        connection.send(content: payload, completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error { self.finish(false, error.localizedDescription); return }
                let receive: @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void = { [weak self] data, _, _, error in
                    Task { @MainActor in
                        guard let self else { return }
                        self.finish(data == self.payload, error?.localizedDescription ?? (data == self.payload ? "Echo verified" : "Echo missing or incorrect"))
                    }
                }
                if self.udp { self.connection.receiveMessage(completion: receive) }
                else { self.connection.receive(minimumIncompleteLength: self.payload.count, maximumLength: self.payload.count, completion: receive) }
            }
        })
    }
    private func finish(_ success: Bool, _ detail: String) {
        guard let continuation = reply else { return }
        reply = nil; timeout?.cancel(); timeout = nil; connection.cancel()
        continuation.resume(returning: (success, detail))
    }
}
