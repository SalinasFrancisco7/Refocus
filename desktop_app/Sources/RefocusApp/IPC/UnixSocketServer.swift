import Foundation

// Ignore SIGPIPE to prevent crash when writing to closed socket
private func ignoreSIGPIPE() {
    signal(SIGPIPE, SIG_IGN)
}

struct TabEvent: Codable {
    let type: String
    let url: String
    let title: String?
    let tabId: Int?
    let windowId: Int?
    let timestamp: Int?
}

struct CLIStatusResponse: Codable {
    struct Recent: Codable {
        let host: String
        let url: String
        let timestamp: TimeInterval
    }

    let mode: String
    let menuTitle: String
    let statusLine: String
    let hardModeEnabled: Bool
    let workSecondsRemaining: Int?
    let recentTabs: [Recent]
}

private struct SocketEnvelope: Codable {
    let type: String
}

final class UnixSocketServer {
    var onEvent: ((TabEvent) -> Void)?
    var statusProvider: (() -> CLIStatusResponse?)?

    private var listener: FileHandle?
    private var acceptSource: DispatchSourceRead?
    private let socketPath = "/tmp/refocus.sock"

    func start() {
        ignoreSIGPIPE()
        cleanupExistingSocket()

        let socketFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFd >= 0 else {
            print("[IPC] Failed to create socket")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { path in
            let maxLength = MemoryLayout.size(ofValue: addr.sun_path)
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: maxLength) {
                    memset($0, 0, maxLength)
                    strncpy($0, path, maxLength - 1)
                }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFd, $0, addrLen)
            }
        }

        guard bindResult == 0, listen(socketFd, 5) == 0 else {
            print("[IPC] Failed to bind/listen on socket")
            close(socketFd)
            return
        }

        print("[IPC] Socket server started at \(socketPath)")
        listener = FileHandle(fileDescriptor: socketFd, closeOnDealloc: true)
        acceptSource = DispatchSource.makeReadSource(fileDescriptor: socketFd, queue: .global())
        acceptSource?.setEventHandler { [weak self] in
            self?.acceptConnection(on: socketFd)
        }
        acceptSource?.resume()
    }

    private func acceptConnection(on socketFd: Int32) {
        var addr = sockaddr()
        var len: socklen_t = socklen_t(MemoryLayout<sockaddr>.size)
        let clientFd = withUnsafeMutablePointer(to: &addr) {
            accept(socketFd, $0, &len)
        }
        guard clientFd >= 0 else {
            return
        }

        let clientHandle = FileHandle(fileDescriptor: clientFd, closeOnDealloc: true)
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            self?.streamMessages(from: clientHandle)
        }
    }

    private func streamMessages(from handle: FileHandle) {
        var buffer = Data()
        var shouldContinue = true
        while shouldContinue {
            autoreleasepool {
                do {
                    let chunk = try handle.read(upToCount: 4096)
                    guard let chunk, !chunk.isEmpty else {
                        handle.closeFile()
                        shouldContinue = false
                        return
                    }
                    buffer.append(chunk)
                    let connectionClosed = processBuffer(&buffer, via: handle)
                    if connectionClosed {
                        shouldContinue = false
                    }
                } catch {
                    handle.closeFile()
                    shouldContinue = false
                }
            }
        }
    }

    @discardableResult
    private func processBuffer(_ buffer: inout Data, via handle: FileHandle) -> Bool {
        var connectionClosed = false
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let messageData = buffer.subdata(in: 0..<newlineIndex)
            buffer.removeSubrange(0...newlineIndex)
            guard !messageData.isEmpty else { continue }

            guard let envelope = try? JSONDecoder().decode(SocketEnvelope.self, from: messageData) else {
                continue
            }

            switch envelope.type {
            case "TAB_EVENT":
                if let event = try? JSONDecoder().decode(TabEvent.self, from: messageData) {
                    onEvent?(event)
                }
            case "CLI_STATUS":
                sendStatusResponse(via: handle)
                connectionClosed = true
            case "PING":
                sendPingResponse(via: handle)
                connectionClosed = true
            default:
                break
            }
        }
        return connectionClosed
    }

    private func sendStatusResponse(via handle: FileHandle) {
        guard let status = statusProvider?(),
              let data = try? JSONEncoder().encode(status) else {
            handle.closeFile()
            return
        }
        var payload = data
        payload.append(0x0A)
        do {
            try handle.write(contentsOf: payload)
        } catch {
            // Broken pipe is expected if client disconnected
        }
        handle.closeFile()
    }

    private func sendPingResponse(via handle: FileHandle) {
        let response: [String: Any] = ["type": "PONG", "timestamp": Int(Date().timeIntervalSince1970)]
        guard let data = try? JSONSerialization.data(withJSONObject: response) else {
            handle.closeFile()
            return
        }
        var payload = data
        payload.append(0x0A)
        do {
            try handle.write(contentsOf: payload)
        } catch {
            // Broken pipe is expected - native host closes connection immediately
        }
        handle.closeFile()
    }

    private func cleanupExistingSocket() {
        unlink(socketPath)
    }
}
