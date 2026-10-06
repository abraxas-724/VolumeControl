import Combine

@MainActor
final class InterfacePreferences: ObservableObject {
    @Published var options: InterfaceOptions {
        didSet { if options != oldValue { storage.save(options) } }
    }
    private let storage: any InterfacePreferenceStoring

    init(storage: any InterfacePreferenceStoring) {
        self.storage = storage
        options = storage.load()
    }

    func resetAppearance() { options = InterfaceOptions() }
}
