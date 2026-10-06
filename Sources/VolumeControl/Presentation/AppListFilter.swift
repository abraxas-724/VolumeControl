import Foundation

enum AppListFilter: String, CaseIterable, Identifiable {
    case all, enabled

    var id: Self { self }
    var label: String { self == .all ? "全部应用" : "已启用" }

    // 已记住但等待重新验证的应用仍能被找到和停止；筛选不会触发捕获。
    func applications(from apps: [AppVolume], matching query: String) -> [AppVolume] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return apps.filter { app in
            let included = self == .all || app.capability.isSupported || app.isRemembered || app.isPreparing
            return included && (search.isEmpty || app.name.localizedStandardContains(search))
        }
    }
}
