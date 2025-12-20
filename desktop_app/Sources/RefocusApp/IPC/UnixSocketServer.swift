import Foundation

struct TabEvent: Codable {
    let type: String
    let url: String
    let title: String?
    let tabId: Int?
    let windowId: Int?
    let timestamp: Int?
}

final class UnixSocketServer {
    var onEvent: ((TabEvent) -> Void)?

    private var listener: FileHandle?
    private var acceptSource: DispatchSourceRead?
    private let socketPath = "/tmp/refocus.sock"

    func start() {
        cleanupExistingSocket()

        let socketFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFd >= 0 else {
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathData = socketPath.data(using: .utf8) ?? Data()
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { pointer in
            pathData.copyBytes(to: UnsafeMutableBufferPointer(start: pointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout.size(ofValue: addr.sun_path)) { $0 }, count: MemoryLayout.size(ofValue: addr.sun_path)))
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFd, $0, addrLen)
            }
        }

        guard bindResult == 0, listen(socketFd, 5) == 0 else {
            close(socketFd)
            return
        }

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
        DispatchQueue.global().async { [weak self] in
            self?.readLines(from: clientHandle)
        }
    }

    private func readLines(from handle: FileHandle) {
        let data = handle.readDataToEndOfFile()
        guard let payload = String(data: data, encoding: .utf8) else {
            return
        }

        for line in payload.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8) else {
                continue
            }
            if let event = try? JSONDecoder().decode(TabEvent.self, from: lineData) {
                onEvent?(event)
            }
        }
    }

    private func cleanupExistingSocket() {
        unlink(socketPath)
    }
}
