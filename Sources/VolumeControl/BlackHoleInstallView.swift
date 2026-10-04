import SwiftUI

struct BlackHoleInstallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isInstalling = false
    let installGuide: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("BlackHole 安装指南")
                        .font(.title2.bold())
                    Text("启用应用级音量控制")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            // Installation Guide
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(installGuide)
                        .font(.body)
                        .textSelection(.enabled)
                    
                    // Quick Install Button
                    VStack(alignment: .leading, spacing: 12) {
                        Text("快速安装 (推荐)")
                            .font(.headline)
                        
                        HStack(spacing: 12) {
                            Button {
                                installViaHomebrew()
                            } label: {
                                Label("使用 Homebrew 安装", systemImage: "terminal")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isInstalling)
                            
                            if isInstalling {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                        
                        Text("将在终端中执行: brew install blackhole-2ch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                    
                    // Manual Install
                    VStack(alignment: .leading, spacing: 8) {
                        Text("手动安装")
                            .font(.headline)
                        
                        Link("下载 BlackHole 安装包", 
                             destination: URL(string: "https://github.com/ExistentialAudio/BlackHole/releases")!)
                            .font(.body)
                    }
                    
                    // Verification
                    VStack(alignment: .leading, spacing: 8) {
                        Text("验证安装")
                            .font(.headline)
                        
                        Text("安装完成后，请前往：")
                            .font(.body)
                        Text("系统设置 → 声音 → 输出")
                            .font(.body.monospaced())
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(4)
                        Text("应该看到 \"BlackHole 2ch\" 设备")
                            .font(.body)
                    }
                }
            }
            .frame(maxHeight: 400)
            
            Divider()
            
            // Footer
            HStack {
                Button("稍后安装") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 600, height: 700)
    }
    
    private func installViaHomebrew() {
        isInstalling = true
        
        Task {
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["brew", "install", "blackhole-2ch"]
                
                try process.run()
                process.waitUntilExit()
                
                await MainActor.run {
                    isInstalling = false
                    if process.terminationStatus == 0 {
                        // Success - show alert and close
                        let alert = NSAlert()
                        alert.messageText = "安装成功"
                        alert.informativeText = "BlackHole 已成功安装。请重启 VolumeControl 以启用应用级音量控制。"
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "确定")
                        alert.runModal()
                        dismiss()
                    } else {
                        // Failed
                        let alert = NSAlert()
                        alert.messageText = "安装失败"
                        alert.informativeText = "自动安装失败。请尝试手动安装或检查 Homebrew 是否已安装。"
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "确定")
                        alert.runModal()
                    }
                }
            } catch {
                await MainActor.run {
                    isInstalling = false
                    let alert = NSAlert()
                    alert.messageText = "启动安装失败"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "确定")
                    alert.runModal()
                }
            }
        }
    }
}

#Preview {
    BlackHoleInstallView(installGuide: """
    
    📦 BlackHole 安装指南
    
    方法 1: 使用 Homebrew (推荐)
    ────────────────────────────
    brew install blackhole-2ch
    
    方法 2: 手动下载
    ────────────────────────────
    1. 访问: https://github.com/ExistentialAudio/BlackHole/releases
    2. 下载: BlackHole2ch.vX.X.X.pkg
    3. 双击安装
    4. 重启 VolumeControl
    
    验证安装:
    ────────────────────────────
    系统设置 → 声音 → 输出
    应该看到 "BlackHole 2ch"
    
    """)
}
