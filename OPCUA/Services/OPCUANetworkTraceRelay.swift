import Foundation
@preconcurrency import NIOCore
@preconcurrency import NIOPosix

nonisolated enum OPCUANetworkCaptureDirection {
    case sent
    case received
}

nonisolated final class OPCUANetworkTraceRelay {
    struct Target {
        let endpointURL: String
        let host: String
        let port: Int
        let path: String

        var localEndpointPath: String {
            path.isEmpty ? "" : path
        }

        static func parse(endpointURL: String, defaultPort: Int = 4840) -> Target? {
            guard let url = URL(string: endpointURL),
                  url.scheme == "opc.tcp",
                  let host = url.host else {
                return nil
            }

            return Target(
                endpointURL: endpointURL,
                host: host,
                port: url.port ?? defaultPort,
                path: url.path
            )
        }
    }

    private let target: Target
    private let analyzer: OPCUANetworkCaptureAnalyzer
    private let stateLock = NSLock()
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?

    private(set) var localEndpoint: String?

    init(serverName: String, target: Target) {
        self.target = target
        self.analyzer = OPCUANetworkCaptureAnalyzer(serverName: serverName, endpointURL: target.endpointURL)
    }

    var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return serverChannel != nil
    }

    func start() throws -> String {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        do {
            let bootstrap = ServerBootstrap(group: group)
                .serverChannelOption(ChannelOptions.backlog, value: 16)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
                .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
                .childChannelInitializer { [target, analyzer] channel in
                    channel.pipeline.addHandler(OPCUANetworkTraceFrontendHandler(
                        remoteHost: target.host,
                        remotePort: target.port,
                        analyzer: analyzer
                    ))
                }

            let channel = try bootstrap.bind(host: "127.0.0.1", port: 0).wait()
            guard let port = channel.localAddress?.port else {
                try channel.close().wait()
                try group.syncShutdownGracefully()
                throw OPCUANetworkTraceRelayError.missingLocalPort
            }

            let endpoint = "opc.tcp://127.0.0.1:\(port)\(target.localEndpointPath)"
            stateLock.lock()
            eventLoopGroup = group
            serverChannel = channel
            localEndpoint = endpoint
            stateLock.unlock()
            return endpoint
        } catch {
            try? group.syncShutdownGracefully()
            throw error
        }
    }

    func stop() {
        stateLock.lock()
        let channel = serverChannel
        let group = eventLoopGroup
        serverChannel = nil
        eventLoopGroup = nil
        localEndpoint = nil
        stateLock.unlock()

        try? channel?.close().wait()
        try? group?.syncShutdownGracefully()
    }
}

nonisolated enum OPCUANetworkTraceRelayError: Error {
    case missingLocalPort
}

nonisolated final class OPCUANetworkCaptureAnalyzer: @unchecked Sendable {
    private struct CapturedFrame {
        let type: String
        let data: Data
    }

    // Symmetric MSG layout: 8-byte frame header + 4 secureChannelId + 4 tokenId
    // + 4 sequenceNumber + 4 requestId = 24 bytes before the request TypeId.
    private static let symmetricBodyOffset = 24

    // FourByte NodeId encoding (0x01) for namespace 0 (0x00) followed by a
    // little-endian UInt16 identifier. Requests whose body could carry a user
    // password (UserNameIdentityToken) are redacted before the bytes ever leave
    // this analyzer, so future changes that expand packet capture (e.g. raise
    // the 32-byte preview limit, persist full frames) cannot leak credentials.
    private static let activateSessionRequestNodeIdBytes: [UInt8] = [0x01, 0x00, 0xD3, 0x01] // id 467

    private let lock = NSLock()
    private let serverName: String
    private let endpointURL: String
    private var sentBuffer = Data()
    private var receivedBuffer = Data()
    private let maxFrameLength = 16 * 1024 * 1024
    private let maxBufferedBytes = 512 * 1024

    init(serverName: String, endpointURL: String) {
        self.serverName = serverName
        self.endpointURL = endpointURL
    }

    func capture(direction: OPCUANetworkCaptureDirection, buffer: ByteBuffer) {
        var copy = buffer
        guard let bytes = copy.readBytes(length: copy.readableBytes), !bytes.isEmpty else {
            return
        }

        capture(direction: direction, bytes: bytes)
    }

    func capture(direction: OPCUANetworkCaptureDirection, bytes: [UInt8]) {
        let frames: [CapturedFrame]

        lock.lock()
        switch direction {
        case .sent:
            sentBuffer.append(contentsOf: bytes)
            frames = extractFrames(from: &sentBuffer)
        case .received:
            receivedBuffer.append(contentsOf: bytes)
            frames = extractFrames(from: &receivedBuffer)
        }
        lock.unlock()

        for frame in frames {
            let (recordedType, recordedData) = redactIfSensitive(frame: frame)
            Task { @MainActor in
                DiagnosticsManager.shared.recordPacket(
                    type: recordedType,
                    direction: direction == .sent ? .sent : .received,
                    size: recordedData.count,
                    data: recordedData
                )
            }
        }
    }

    private func redactIfSensitive(frame: CapturedFrame) -> (type: String, data: Data) {
        guard frame.type.hasPrefix("MSG"),
              frame.data.count >= Self.symmetricBodyOffset + Self.activateSessionRequestNodeIdBytes.count else {
            return (frame.type, frame.data)
        }

        let typeIdRange = Self.symmetricBodyOffset..<(Self.symmetricBodyOffset + Self.activateSessionRequestNodeIdBytes.count)
        let typeIdBytes = Array(frame.data[typeIdRange])
        guard typeIdBytes == Self.activateSessionRequestNodeIdBytes else {
            return (frame.type, frame.data)
        }

        var redacted = frame.data
        let bodyStart = Self.symmetricBodyOffset
        redacted.replaceSubrange(bodyStart..<redacted.count,
                                 with: Data(repeating: 0x00, count: redacted.count - bodyStart))
        return ("\(frame.type) [redacted]", redacted)
    }

    func recordConnectionFailure(_ message: String) {
        Task { @MainActor in
            DiagnosticsManager.shared.log(
                "\(serverName) network trace relay failed for \(endpointURL): \(message)",
                level: .warning,
                component: "NetworkTrace"
            )
            DiagnosticsManager.shared.recordMessageError()
        }
    }

    private func extractFrames(from buffer: inout Data) -> [CapturedFrame] {
        var frames: [CapturedFrame] = []

        while buffer.count >= 8 {
            let header = Array(buffer.prefix(8))
            guard let messageType = messageType(from: header) else {
                let rawLength = min(buffer.count, 4096)
                frames.append(CapturedFrame(type: "TCP", data: Data(buffer.prefix(rawLength))))
                buffer.removeFirst(rawLength)
                continue
            }

            let length = Int(UInt32(header[4]) |
                (UInt32(header[5]) << 8) |
                (UInt32(header[6]) << 16) |
                (UInt32(header[7]) << 24))

            guard length >= 8, length <= maxFrameLength else {
                let rawLength = min(buffer.count, 4096)
                frames.append(CapturedFrame(type: "TCP", data: Data(buffer.prefix(rawLength))))
                buffer.removeFirst(rawLength)
                continue
            }

            guard buffer.count >= length else {
                break
            }

            frames.append(CapturedFrame(type: messageType, data: Data(buffer.prefix(length))))
            buffer.removeFirst(length)
        }

        if buffer.count > maxBufferedBytes {
            frames.append(CapturedFrame(type: "TCP", data: Data(buffer.prefix(maxBufferedBytes))))
            buffer.removeFirst(maxBufferedBytes)
        }

        return frames
    }

    private func messageType(from header: [UInt8]) -> String? {
        let type = String(decoding: header[0..<3], as: UTF8.self)
        guard ["HEL", "ACK", "ERR", "RHE", "OPN", "MSG", "CLO"].contains(type),
              let scalar = UnicodeScalar(Int(header[3])) else {
            return nil
        }

        return "\(type)/\(Character(scalar))"
    }
}

nonisolated final class OPCUANetworkTraceFrontendHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let remoteHost: String
    private let remotePort: Int
    private let analyzer: OPCUANetworkCaptureAnalyzer
    private var outboundChannel: Channel?
    private var pendingReads: [NIOAny] = []

    init(remoteHost: String, remotePort: Int, analyzer: OPCUANetworkCaptureAnalyzer) {
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.analyzer = analyzer
    }

    func channelActive(context: ChannelHandlerContext) {
        let peerChannel = context.channel
        let bootstrap = ClientBootstrap(group: context.eventLoop)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .channelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
            .channelInitializer { [analyzer] channel in
                channel.pipeline.addHandler(OPCUANetworkTraceBackendHandler(
                    peerChannel: peerChannel,
                    analyzer: analyzer
                ))
            }

        bootstrap.connect(host: remoteHost, port: remotePort).whenComplete { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let channel):
                self.outboundChannel = channel
                self.flushPendingReads()
            case .failure(let error):
                self.analyzer.recordConnectionFailure(error.localizedDescription)
                peerChannel.close(promise: nil)
            }
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if outboundChannel == nil {
            pendingReads.append(data)
            return
        }

        forward(data)
    }

    func channelInactive(context: ChannelHandlerContext) {
        outboundChannel?.close(promise: nil)
        outboundChannel = nil
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        analyzer.recordConnectionFailure(error.localizedDescription)
        context.close(promise: nil)
    }

    private func flushPendingReads() {
        let reads = pendingReads
        pendingReads.removeAll()
        for data in reads {
            forward(data)
        }
    }

    private func forward(_ data: NIOAny) {
        guard let outboundChannel else { return }
        let buffer = unwrapInboundIn(data)
        analyzer.capture(direction: .sent, buffer: buffer)
        outboundChannel.writeAndFlush(buffer, promise: nil)
    }
}

nonisolated final class OPCUANetworkTraceBackendHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let peerChannel: Channel
    private let analyzer: OPCUANetworkCaptureAnalyzer

    init(peerChannel: Channel, analyzer: OPCUANetworkCaptureAnalyzer) {
        self.peerChannel = peerChannel
        self.analyzer = analyzer
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        analyzer.capture(direction: .received, buffer: buffer)
        peerChannel.writeAndFlush(buffer, promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        peerChannel.close(promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        analyzer.recordConnectionFailure(error.localizedDescription)
        context.close(promise: nil)
    }
}
