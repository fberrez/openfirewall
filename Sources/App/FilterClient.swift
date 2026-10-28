import Foundation

final class ReplyOnce<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    init(_ continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }
    func finish(_ result: Result<Value, Error>) {
        lock.lock(); let continuation = self.continuation; self.continuation = nil; lock.unlock()
        continuation?.resume(with: result)
    }
}

@MainActor
final class FilterClient {
    private var connection: NSXPCConnection?
    private func connect() throws -> NSXPCConnection {
        if let connection { return connection }
        guard let requirement = ProductConfiguration.requirement(for: ProductConfiguration.filterIdentifier),
              !ProductConfiguration.serviceName.isEmpty else {
            throw clientError("A signed build is needed to connect to the network filter.")
        }
        let connection = NSXPCConnection(machServiceName: ProductConfiguration.serviceName, options: .privileged)
        connection.setCodeSigningRequirement(requirement)
        connection.remoteObjectInterface = NSXPCInterface(with: FirewallControlProtocol.self)
        connection.invalidationHandler = { [weak self] in Task { @MainActor in self?.connection = nil } }
        connection.resume(); self.connection = connection
        return connection
    }
    func snapshot() async throws -> ProviderSnapshot {
        let connection = try connect()
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            let once = ReplyOnce(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { once.finish(.failure($0)) } as? FirewallControlProtocol
            proxy?.snapshot { data, error in
                if let data { once.finish(.success(data)) }
                else { once.finish(.failure(clientError(error ?? "The filter did not return its status."))) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { once.finish(.failure(clientError("The network filter is not responding."))) }
        }
        return try WireCodec.decode(ProviderSnapshot.self, from: data)
    }
    func apply(_ policy: FirewallPolicy) async throws {
        let connection = try connect(); let data = try WireCodec.encode(policy)
        let _: Bool = try await withCheckedThrowingContinuation { continuation in
            let once = ReplyOnce(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { once.finish(.failure($0)) } as? FirewallControlProtocol
            proxy?.applyPolicy(data) { error in
                once.finish(error.map { .failure(clientError($0)) } ?? .success(true))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { once.finish(.failure(clientError("The rule update was not acknowledged."))) }
        }
    }
    func clear() async throws {
        let connection = try connect()
        let _: Bool = try await withCheckedThrowingContinuation { continuation in
            let once = ReplyOnce(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { once.finish(.failure($0)) } as? FirewallControlProtocol
            proxy?.clearHistory { once.finish(.success(true)) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { once.finish(.failure(clientError("Could not clear the filter history."))) }
        }
    }
}

func clientError(_ message: String) -> NSError {
    NSError(domain: "org.openfirewall", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
