import Foundation

/// tap 回调和播放完成回调跨线程运行；按时长和数量限制排队，旧会话不能释放新会话的缓冲。
final class AudioBufferBudget {
    struct Ticket: Hashable {
        fileprivate let generation: Int
        fileprivate let id: Int
    }

    private let lock = NSLock()
    private let maximumBuffers: Int
    private let maximumDuration: Double
    private var generation = 0
    private var nextID = 0
    private var active = true
    private var pending: [Ticket: Double] = [:]

    init(maximumBuffers: Int = 4, maximumDuration: Double = 0.25) {
        self.maximumBuffers = maximumBuffers
        self.maximumDuration = maximumDuration
    }

    func reserve(duration: Double) -> Ticket? {
        lock.lock()
        defer { lock.unlock() }
        guard active, duration.isFinite, duration > 0,
              pending.count < maximumBuffers,
              pending.values.reduce(0, +) + duration <= maximumDuration else { return nil }
        nextID += 1
        let ticket = Ticket(generation: generation, id: nextID)
        pending[ticket] = duration
        return ticket
    }

    func contains(_ ticket: Ticket) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return active && pending[ticket] != nil
    }

    func finish(_ ticket: Ticket) {
        lock.lock()
        defer { lock.unlock() }
        pending.removeValue(forKey: ticket)
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        active = false
        generation += 1
        pending.removeAll()
    }
}
