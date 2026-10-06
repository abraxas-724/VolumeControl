import Combine

@MainActor
final class InterfacePreferences: ObservableObject {
    @Published var options: InterfaceOptions {
        didSet { if options != oldValue { storage.save(options) } }
    }
    private let storage: any InterfacePreferenceStoring

    init(storage: any InterfacePreferenceStoring) {
        self.storage = storage
        var loaded = storage.load()
        // 旧版灵动指页面内部反馈；迁移为原生弹出，不在加载时改写偏好。
        if loaded.motion == .playful { loaded.motion = .subtle }
        options = loaded
    }

    func resetAppearance() { options = InterfaceOptions() }
}
