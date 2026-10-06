import AppKit

@main
@MainActor
enum VolumeControlApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = VolumeControlApplicationDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}
