import Foundation
import NetworkExtension
import SystemExtensions

@MainActor
final class SystemSetup: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {
    @Published var message = "Install in /Applications, then enable."
    @Published var busy = false
    @Published var enabled = false
    private var activation: CheckedContinuation<Void, Error>?
    private var activationRequest: OSSystemExtensionRequest?
    private var inspection: CheckedContinuation<Bool, Error>?
    private var inspectionRequest: OSSystemExtensionRequest?
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
            if !busy {
                message = enabled ? "Enabled" : "Enable, then approve in macOS."
            }
        }
        catch { message = "Setup required." }
    }
    func enable(policy: FirewallPolicy) async throws {
        guard !busy else { return }
        guard ProductConfiguration.requirement(for: ProductConfiguration.appIdentifier) != nil else {
            throw clientError("Unsigned build. Install a signed release to enable filtering.")
        }
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else {
            throw clientError("Move the signed OpenFirewall app to Applications before enabling it.")
        }
        busy = true; defer { busy = false }
        message = "Requesting macOS approval…"
        if try await !currentExtensionIsEnabled() {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                activation = continuation
                let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: ProductConfiguration.filterIdentifier, queue: .main)
                activationRequest = request
                request.delegate = self
                OSSystemExtensionManager.shared.submitRequest(request)
            }
        }
        try await persist(policy, enable: true)
        enabled = true; message = "Waiting for filter…"
    }
    private func currentExtensionIsEnabled() async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            inspection = continuation
            let request = OSSystemExtensionRequest.propertiesRequest(forExtensionWithIdentifier: ProductConfiguration.filterIdentifier, queue: .main)
            inspectionRequest = request
            request.delegate = self
            OSSystemExtensionManager.shared.submitRequest(request)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard let self, self.inspectionRequest === request else { return }
                let continuation = self.inspection
                self.inspection = nil; self.inspectionRequest = nil
                continuation?.resume(throwing: clientError("macOS did not return the installation status. Try enabling the firewall again."))
            }
        }
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
        enabled = false; message = "Disabled"
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
        Task { @MainActor in
            guard self.activationRequest === request else { return }
            self.message = "Approve OpenFirewall in System Settings → General → Login Items & Extensions → Network Extensions."
        }
    }
    nonisolated func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        Task { @MainActor in
            guard self.inspectionRequest === request else { return }
            let path = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/SystemExtensions/\(ProductConfiguration.filterIdentifier).systemextension")
            let info = Bundle(url: path)?.infoDictionary
            let current = properties.contains {
                $0.isEnabled && !$0.isUninstalling && $0.bundleVersion == info?["CFBundleVersion"] as? String &&
                    $0.bundleShortVersion == info?["CFBundleShortVersionString"] as? String
            }
            let continuation = self.inspection
            self.inspection = nil; self.inspectionRequest = nil
            continuation?.resume(returning: current)
        }
    }
    nonisolated func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties,
                             withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction { .replace }
    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Task { @MainActor in
            guard self.activationRequest === request else { return }
            let continuation = self.activation; self.activation = nil; self.activationRequest = nil
            if result == .willCompleteAfterReboot {
                continuation?.resume(throwing: clientError("Restart your Mac to finish enabling the extension, then enable the firewall again."))
            } else { continuation?.resume() }
        }
    }
    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        Task { @MainActor in
            if self.inspectionRequest === request {
                let continuation = self.inspection
                self.inspection = nil; self.inspectionRequest = nil
                continuation?.resume(throwing: error)
            } else if self.activationRequest === request {
                let continuation = self.activation
                self.activation = nil; self.activationRequest = nil
                continuation?.resume(throwing: error)
            }
        }
    }
}
