import AVFoundation
import Foundation

protocol AudioInputPermissionProviding {
    func requestAccess() async throws -> Bool
}

/// 系统主音量不需要录音权限；仅在用户启动 BlackHole 输入验证时请求。
struct AudioInputPermission: AudioInputPermissionProviding {
    func requestAccess() async throws -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else {
                throw AudioRoutingError.engineFailed("请使用 scripts/build-app.sh 打包的应用启动路由验证，以提供录音权限说明")
            }
            return await AVCaptureDevice.requestAccess(for: .audio)
        @unknown default: return false
        }
    }
}
