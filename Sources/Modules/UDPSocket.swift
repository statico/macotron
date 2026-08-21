import Darwin
import Foundation

enum UDPCodec {
    static func encode(_ value: Any) -> Data? {
        if let data = value as? Data { return data }
        if let s = value as? String { return Data(s.utf8) }
        if let arr = value as? [UInt8] { return Data(arr) }
        if let arr = value as? [Int] {
            var bytes: [UInt8] = []
            bytes.reserveCapacity(arr.count)
            for i in arr {
                guard (0...255).contains(i) else { return nil }
                bytes.append(UInt8(i))
            }
            return Data(bytes)
        }
        if let arr = value as? [Any] {
            var bytes: [UInt8] = []
            bytes.reserveCapacity(arr.count)
            for item in arr {
                guard let b = byte(item) else { return nil }
                bytes.append(b)
            }
            return Data(bytes)
        }
        return nil
    }

    static func decode(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        return data.base64EncodedString()
    }

    private static func byte(_ value: Any) -> UInt8? {
        if let i = value as? Int, (0...255).contains(i) { return UInt8(i) }
        if let n = value as? NSNumber {
            let i = n.intValue
            return (0...255).contains(i) ? UInt8(i) : nil
        }
        return nil
    }
}

final class UDPHub: @unchecked Sendable {
    private let lock = NSLock()
    private var sockets: [Int: Int32] = [:]
    var onMessage: ((String, Int, String) -> Void)?

    func send(host: String, port: Int, data: Data) -> [String: Any] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return ["ok": false, "error": "socket"] }
        defer { Darwin.close(fd) }

        var hints = addrinfo(
            ai_flags: AI_NUMERICSERV,
            ai_family: AF_INET,
            ai_socktype: SOCK_DGRAM,
            ai_protocol: IPPROTO_UDP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var res: UnsafeMutablePointer<addrinfo>?
        let err = getaddrinfo(host, String(port), &hints, &res)
        guard err == 0, let info = res else {
            return ["ok": false, "error": String(cString: gai_strerror(err))]
        }
        defer { freeaddrinfo(res) }

        let n = data.withUnsafeBytes { buf in
            sendto(fd, buf.baseAddress, buf.count, 0, info.pointee.ai_addr, info.pointee.ai_addrlen)
        }
        if n < 0 {
            return ["ok": false, "error": String(cString: strerror(errno))]
        }
        return ["ok": true]
    }

    func listen(port: Int) -> [String: Any] {
        lock.lock()
        if sockets[port] != nil {
            lock.unlock()
            return ["ok": true]
        }
        lock.unlock()

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return ["ok": false, "error": "socket"] }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(clamping: port)).bigEndian
        addr.sin_addr = in_addr(s_addr: INADDR_ANY)

        let bindOk = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindOk != 0 {
            Darwin.close(fd)
            return ["ok": false, "error": String(cString: strerror(errno))]
        }

        lock.lock()
        sockets[port] = fd
        lock.unlock()
        Thread.detachNewThread { [weak self] in
            self?.recvLoop(port: port, fd: fd)
        }
        return ["ok": true]
    }

    func unlisten(port: Int) {
        lock.lock()
        let fd = sockets.removeValue(forKey: port)
        lock.unlock()
        if let fd { Darwin.close(fd) }
    }

    func cleanup() {
        lock.lock()
        let fds = Array(sockets.values)
        sockets.removeAll()
        lock.unlock()
        for fd in fds { Darwin.close(fd) }
    }

    private func recvLoop(port: Int, fd: Int32) {
        var buf = [UInt8](repeating: 0, count: 65_535)
        while true {
            var src = sockaddr_in()
            var srclen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &src) { srcPtr in
                srcPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(fd, &buf, buf.count, 0, sa, &srclen)
                }
            }
            if n <= 0 { break }
            var hostBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            _ = inet_ntop(AF_INET, &src.sin_addr, &hostBuf, socklen_t(INET_ADDRSTRLEN))
            let host = String(
                decoding: hostBuf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                as: UTF8.self
            )
            let fromPort = Int(UInt16(bigEndian: src.sin_port))
            let payload = UDPCodec.decode(Data(buf.prefix(Int(n))))
            onMessage?(host, fromPort, payload)
        }
        lock.lock()
        if sockets[port] == fd { sockets.removeValue(forKey: port) }
        lock.unlock()
        Darwin.close(fd)
    }
}
