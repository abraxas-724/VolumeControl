import AppKit
import Combine
import SwiftUI

/// 使用系统锚定弹出机制管理整个窗口；SwiftUI 内容不承担窗口显隐动画。
@MainActor
final class MenuBarPopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let hosting: NSHostingController<AnyView>
    private let layout = PanelPresentationContext()
    private let preferences: InterfacePreferences
    private let beforeOpening: () -> Void
    private let reduceMotion: () -> Bool
    private let reduceTransparency: () -> Bool
    private var statusItem: NSStatusItem?
    private var preferencesSubscription: AnyCancellable?
    private var resizeTask: Task<Void, Never>?
    private let workspaceNotifications: NotificationCenter
    private var accessibilityObserver: NSObjectProtocol?
    private var muted = false
    private var volume: Double? = 0.5
    private var statusSymbolName: String?

    var isShown: Bool { popover.isShown }
    var animates: Bool { popover.animates }
    var presentationWindow: NSWindow? { hosting.view.window }
    var statusButton: NSStatusBarButton? { statusItem?.button }

    init(preferences: InterfacePreferences, content: AnyView,
         beforeOpening: @escaping () -> Void = {}, reduceMotion: (() -> Bool)? = nil,
         reduceTransparency: (() -> Bool)? = nil, workspaceNotifications: NotificationCenter? = nil) {
        self.preferences = preferences
        hosting = NSHostingController(rootView: AnyView(PanelHostedContent(content: content, layout: layout)))
        self.beforeOpening = beforeOpening
        self.reduceMotion = reduceMotion ?? { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        self.reduceTransparency = reduceTransparency ?? { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
        self.workspaceNotifications = workspaceNotifications ?? NSWorkspace.shared.notificationCenter
        super.init()
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.delegate = self
        preferencesSubscription = preferences.$options.sink { [weak self] options in
            self?.apply(options)
            self?.scheduleResize()
        }
        accessibilityObserver = self.workspaceNotifications.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.apply(self.preferences.options)
            }
        }
    }

    deinit {
        resizeTask?.cancel()
        if let accessibilityObserver { workspaceNotifications.removeObserver(accessibilityObserver) }
    }

    func start() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(toggleFromStatusItem)
        item.button?.setAccessibilityLabel("VolumeControl 音量面板")
        item.button?.toolTip = "VolumeControl"
        statusItem = item
        updateStatusImage()
    }

    func setSystemAudio(volume: Double?, muted: Bool) {
        self.volume = volume
        self.muted = muted
        updateStatusImage()
    }

    private func updateStatusImage() {
        let symbol = MenuBarVolumeSymbol.name(volume: volume, muted: muted)
        guard statusSymbolName != symbol || statusItem?.button?.image == nil else { return }
        statusSymbolName = symbol
        let image = NSImage(systemSymbolName: symbol,
                            accessibilityDescription: "VolumeControl")
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    @objc private func toggleFromStatusItem() {
        guard let button = statusButton else { return }
        toggle(relativeTo: button)
    }

    func toggle(relativeTo anchor: NSView) {
        if popover.isShown { close(); return }
        beforeOpening()
        apply(preferences.options)
        updateContentSize(anchor: anchor)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        apply(preferences.options)
        // 菜单栏应用不必激活其他窗口；让搜索框能接收键盘输入。
        hosting.view.window?.makeKey()
        scheduleResize()
    }

    func close() {
        resizeTask?.cancel()
        popover.performClose(nil)
    }

    func stop() {
        popover.animates = false
        popover.close()
        resizeTask?.cancel()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool { false }
    func popoverWillClose(_ notification: Notification) { resizeTask?.cancel() }

    func scheduleResize() {
        guard isShown else { return }
        resizeTask?.cancel()
        resizeTask = Task { [weak self] in
            // 等待 SwiftUI 合并已发布的状态，避免按旧偏好测量尺寸。
            do { try await Task.sleep(nanoseconds: 20_000_000) } catch { return }
            guard let self, !Task.isCancelled, self.isShown else { return }
            self.updateContentSize(anchor: self.statusButton)
        }
    }

    private func apply(_ options: InterfaceOptions) {
        popover.animates = options.allowsMotion(reduceMotion: reduceMotion())
        switch options.theme {
        case .system: popover.appearance = nil
        case .light: popover.appearance = NSAppearance(named: .aqua)
        case .dark: popover.appearance = NSAppearance(named: .darkAqua)
        }
        hosting.view.window?.appearance = popover.appearance
        hosting.view.appearance = popover.appearance
        let surface = options.effectiveSurface(nativeGlassAvailable: InterfaceAppearanceSupport.nativeGlassAvailable,
                                               reduceTransparency: reduceTransparency())
        hosting.view.window?.isOpaque = surface == .standard
        hosting.view.window?.backgroundColor = surface == .standard ? .windowBackgroundColor : .clear
        let transparency = reduceTransparency()
        let motion = reduceMotion()
        if layout.reduceTransparency != transparency { layout.reduceTransparency = transparency }
        if layout.reduceMotion != motion { layout.reduceMotion = motion }
    }

    private func updateContentSize(anchor: NSView?) {
        let screen = anchor?.window?.screen ?? hosting.view.window?.screen ?? NSScreen.main
        let availableHeight = max(360, (screen?.visibleFrame.height ?? 900) - 36)
        if layout.maximumHeight != availableHeight { layout.maximumHeight = availableHeight }
        let size = hosting.sizeThatFits(in: NSSize(width: PanelStyle.width, height: availableHeight))
        hosting.view.setFrameSize(size)
        popover.contentSize = size
    }
}

/// 可用屏幕尺寸单独发布，避免更换 SwiftUI 根节点而丢失搜索、焦点和展开状态。
@MainActor
private final class PanelPresentationContext: ObservableObject {
    @Published var maximumHeight: CGFloat = 680
    @Published var reduceTransparency = false
    @Published var reduceMotion = false
}

private struct PanelHostedContent: View {
    let content: AnyView
    @ObservedObject var layout: PanelPresentationContext
    var body: some View {
        content.environment(\.panelMaximumHeight, layout.maximumHeight)
            .environment(\.usesNativePopoverGlass, InterfaceAppearanceSupport.nativeGlassAvailable)
            .environment(\.panelReduceTransparency, layout.reduceTransparency)
            .environment(\.panelReduceMotion, layout.reduceMotion)
    }
}

enum MenuBarVolumeSymbol {
    static func name(volume: Double?, muted: Bool) -> String {
        if muted { return "speaker.slash.fill" }
        guard let volume, volume.isFinite else { return "speaker.wave.2.fill" }
        let value = min(1, max(0, volume))
        if value == 0 { return "speaker.slash.fill" }
        if value <= 0.33 { return "speaker.wave.1.fill" }
        if value <= 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
