import Combine
import Foundation

@MainActor
final class KernelDiscoveryService: ObservableObject {
    private let configLoader: CronaConfigLoader

    @Published var loadedRuntime: LoadedCronaRuntime = LoadedCronaRuntime(config: CronaConfig.placeholder, discovery: nil)

    init(configLoader: CronaConfigLoader) {
        self.configLoader = configLoader
        self.loadedRuntime = configLoader.load()
    }

    func reload() -> LoadedCronaRuntime {
        let runtime = configLoader.load()
        loadedRuntime = runtime
        return runtime
    }
}
