import Foundation
import NetworkExtension
import SystemExtensions

@MainActor
final class SystemSetup: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {
    @Published var message = "Install the signed app in Applications, then enable the firewall."
    @Published var busy = false
    @Published var enabled = false
    private var activation: CheckedContinuation<Void, Error>?
    private var configurationObserver: NSObjectProtocol?

    override init() {
        super.init()
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .NEFilterConfigurationDidChange, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in await self?.load() } }
    }
    deinit { if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) } }

    func load() async {
        do {
            try await loadPreferences()
            enabled = NEFilterManager.shared().isEnabled &&
                NEFilterManager.shared().providerConfiguration?.filterDataProviderBundleIdentifier == ProductConfiguration.filterIdentifier
        }
        catch { message = "Setup is required before connection monitoring can start." }
    }
    func enable(policy: FirewallPolicy) async throws {
        guard !busy else { return }
        guard ProductConfiguration.requirement(for: ProductConfiguration.appIdentifier) != nil else {
            throw clientError("This is an unsigned preview build. Open the Xcode project, choose your signing team, and build a signed app first.")
        }
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else {
            throw clientError("Move the signed OpenFirewall app to Applications before enabling it.")
        }
        busy = true; defer { busy = false }
        message = "Requesting macOS approval…"
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            activation = continuation
            let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: ProductConfiguration.filterIdentifier, queue: .main)
            request.delegate = self
            OSSystemExtensionManager.shared.submitRequest(request)
        }
        try await persist(policy, enable: true)
        enabled = true; message = "Firewall enabled. Waiting for the network filter…"
    }
    func disable() async throws {
        busy = true; defer { busy = false }
        try await loadPreferences()
        let manager = NEFilterManager.shared()
        guard manager.providerConfiguration?.filterDataProviderBundleIdentifier == ProductConfiguration.filterIdentifier else {
            throw clientError("OpenFirewall does not own this filter configuration.")
        }
        manager.isEnabled = false
        try await savePreferences()
        enabled = false; message = "Firewall disabled. Connections are no longer filtered."
    }
    func persist(_ policy: FirewallPolicy, enable: Bool? = nil) async throws {
        let policy = try policy.validated()
        try await loadPreferences()
        let manager = NEFilterManager.shared()
        if let existing = manager.providerConfiguration?.filterDataProviderBundleIdentifier,
           existing != ProductConfiguration.filterIdentifier {
            throw clientError("Another content filter owns this configuration. OpenFirewall will not replace it.")
        }
        let configuration = manager.providerConfiguration ?? NEFilterProviderConfiguration()
        configuration.filterSockets = true; configuration.filterPackets = false
        configuration.filterDataProviderBundleIdentifier = ProductConfiguration.filterIdentifier
        configuration.vendorConfiguration = [ProductConfiguration.policyKey: try WireCodec.encode(policy),
                                               ProductConfiguration.ownerKey: NSNumber(value: getuid())]
        manager.providerConfiguration = configuration
        manager.localizedDescription = "OpenFirewall"
        if let enable { manager.isEnabled = enable }
        try await savePreferences()
    }
    func savedPolicy() async -> FirewallPolicy? {
        try? await loadPreferences()
        guard NEFilterManager.shared().providerConfiguration?.filterDataProviderBundleIdentifier == ProductConfiguration.filterIdentifier,
              let data = NEFilterManager.shared().providerConfiguration?.vendorConfiguration?[ProductConfiguration.policyKey] as? Data else { return nil }
        return try? WireCodec.decode(FirewallPolicy.self, from: data).validated()
    }
    private func loadPreferences() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NEFilterManager.shared().loadFromPreferences { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
    private func savePreferences() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NEFilterManager.shared().saveToPreferences { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor in self.message = "Approve OpenFirewall in System Settings → General → Login Items & Extensions → Network Extensions." }
    }
    nonisolated func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties,
                             withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction { .replace }
    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Task { @MainActor in
            let continuation = self.activation; self.activation = nil
            if result == .willCompleteAfterReboot {
                continuation?.resume(throwing: clientError("Restart your Mac to finish enabling the extension, then enable the firewall again."))
            } else { continuation?.resume() }
        }
    }
    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        Task { @MainActor in let continuation = self.activation; self.activation = nil; continuation?.resume(throwing: error) }
    }
}
