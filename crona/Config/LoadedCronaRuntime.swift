import Foundation

struct LoadedCronaRuntime {
    let config: CronaConfig
    let discovery: CronaKernelDiscovery?
    let resolvedDiscovery: CronaResolvedKernelDiscovery?
    let loadedAt: Date

    init(
        config: CronaConfig,
        discovery: CronaKernelDiscovery?,
        loadedAt: Date = Date()
    ) {
        self.config = config
        self.discovery = discovery
        self.resolvedDiscovery = discovery?.resolved(using: config)
        self.loadedAt = loadedAt
    }
}
