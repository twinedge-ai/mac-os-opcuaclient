import Foundation
import Combine

@MainActor
class DiagnosticsManager: ObservableObject {
    static let shared = DiagnosticsManager()

    // MARK: - Published Properties
    @Published var messagesSent: Int = 0
    @Published var messagesReceived: Int = 0
    @Published var messagesPending: Int = 0
    @Published var messageErrors: Int = 0

    @Published var cpuUsage: Double = 0
    @Published var memoryUsage: Double = 0
    @Published var networkBytesIn: Int = 0
    @Published var networkBytesOut: Int = 0

    @Published var logs: [LogEntry] = []
    @Published var packets: [PacketInfo] = []

    // Historical data for charts
    @Published var cpuHistory: [(Date, Double)] = []
    @Published var memoryHistory: [(Date, Double)] = []
    @Published var networkHistory: [(Date, Double)] = []
    @Published var messagesHistory: [(Date, Double)] = []

    private var updateTimer: Timer?
    private var startTime: Date = Date()
    private var lastMessageCount: Int = 0
    private var messagesPerSecond: Double = 0

    // MARK: - Initialization

    private init() {
        startMonitoring()
    }

    // MARK: - Monitoring

    func startMonitoring() {
        startTime = Date()

        // Update metrics every second
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.updateMetrics()
            }
        }
    }

    func stopMonitoring() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func updateMetrics() {
        let now = Date()

        // Update CPU and Memory from system
        updateSystemMetrics()

        // Calculate messages per second
        let currentTotal = messagesSent + messagesReceived
        messagesPerSecond = Double(currentTotal - lastMessageCount)
        lastMessageCount = currentTotal

        // Add to history (keep last 60 data points)
        cpuHistory.append((now, cpuUsage))
        memoryHistory.append((now, memoryUsage))
        networkHistory.append((now, Double(networkBytesIn + networkBytesOut) / 1024.0))
        messagesHistory.append((now, messagesPerSecond))

        // Trim history to last 60 entries
        if cpuHistory.count > 60 { cpuHistory.removeFirst() }
        if memoryHistory.count > 60 { memoryHistory.removeFirst() }
        if networkHistory.count > 60 { networkHistory.removeFirst() }
        if messagesHistory.count > 60 { messagesHistory.removeFirst() }
    }

    private func updateSystemMetrics() {
        // Get actual process memory usage
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            memoryUsage = Double(info.resident_size) / (1024 * 1024) // Convert to MB
        }

        // Get actual CPU usage from task info
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let threadResult = task_threads(mach_task_self_, &threadList, &threadCount)

        if threadResult == KERN_SUCCESS, let threads = threadList {
            var totalCPU: Double = 0
            let threadBasicInfoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size)

            for i in 0..<Int(threadCount) {
                var threadInfo = thread_basic_info_data_t()
                var threadInfoCount = threadBasicInfoCount

                let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: Int(threadInfoCount)) {
                        thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                    }
                }

                if infoResult == KERN_SUCCESS && (threadInfo.flags & TH_FLAGS_IDLE) == 0 {
                    totalCPU += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                }
            }

            cpuUsage = min(100, totalCPU)

            // Deallocate thread list
            let threadListSize = vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), threadListSize)
        }
    }

    // MARK: - Logging

    func log(_ message: String, level: LogLevel = .info, component: String = "System") {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            component: component,
            message: message
        )

        logs.insert(entry, at: 0)

        // Keep only last 500 log entries
        if logs.count > 500 {
            logs.removeLast()
        }
    }

    func clearLogs() {
        logs.removeAll()
    }

    // MARK: - Packet Tracking

    func recordPacket(type: String, direction: PacketDirection, size: Int, data: Data? = nil) {
        let hexDump = data?.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " ") ?? "No data"

        let packet = PacketInfo(
            timestamp: Date(),
            type: type,
            direction: direction,
            size: size,
            hexDump: hexDump + (data?.count ?? 0 > 32 ? "..." : "")
        )

        packets.insert(packet, at: 0)

        // Update counters
        switch direction {
        case .sent:
            messagesSent += 1
            networkBytesOut += size
        case .received:
            messagesReceived += 1
            networkBytesIn += size
        }

        // Keep only last 200 packets
        if packets.count > 200 {
            packets.removeLast()
        }
    }

    func clearPackets() {
        packets.removeAll()
    }

    // MARK: - Message Statistics

    func recordMessageError() {
        messageErrors += 1
        log("Message error occurred", level: .error, component: "Protocol")
    }

    func incrementPending() {
        messagesPending += 1
    }

    func decrementPending() {
        messagesPending = max(0, messagesPending - 1)
    }

    // MARK: - Computed Properties

    var uptime: String {
        let interval = Date().timeIntervalSince(startTime)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    var formattedMemory: String {
        if memoryUsage >= 1024 {
            return String(format: "%.1f GB", memoryUsage / 1024)
        }
        return String(format: "%.0f MB", memoryUsage)
    }

    var formattedCPU: String {
        return String(format: "%.0f%%", cpuUsage)
    }

    var formattedNetworkIn: String {
        return formatBytes(networkBytesIn)
    }

    var formattedNetworkOut: String {
        return formatBytes(networkBytesOut)
    }

    var formattedMessagesPerSecond: String {
        return String(format: "%.0f/s", messagesPerSecond)
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes >= 1_000_000_000 {
            return String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
        } else if bytes >= 1_000_000 {
            return String(format: "%.1f MB", Double(bytes) / 1_000_000)
        } else if bytes >= 1_000 {
            return String(format: "%.1f KB", Double(bytes) / 1_000)
        }
        return "\(bytes) B"
    }
}

// MARK: - Supporting Types

enum LogLevel: String, CaseIterable {
    case all = "All"
    case error = "Error"
    case warning = "Warning"
    case info = "Info"
    case debug = "Debug"

    var color: String {
        switch self {
        case .error: return "red"
        case .warning: return "orange"
        case .info: return "blue"
        case .debug: return "gray"
        case .all: return "primary"
        }
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let component: String
    let message: String
}

enum PacketDirection {
    case sent, received

    var systemImage: String {
        switch self {
        case .sent: return "arrow.up.circle"
        case .received: return "arrow.down.circle"
        }
    }
}

struct PacketInfo: Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: String
    let direction: PacketDirection
    let size: Int
    let hexDump: String
}
