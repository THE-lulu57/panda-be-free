import Foundation
import Network
import PandaLogger
import Security

private let logCategory = "FTPS"

public struct FTPFileEntry: Sendable, Equatable {
    public let name: String
    public let sizeBytes: Int64
    public let isDirectory: Bool
}

public enum FTPSError: Error, LocalizedError {
    case connectionFailed(String)
    case unexpectedReply(String)
    case dataConnectionFailed

    public var errorDescription: String? {
        switch self {
        case let .connectionFailed(reason): "FTPS connection failed: \(reason)"
        case let .unexpectedReply(reply): "Unexpected FTP reply: \(reply)"
        case .dataConnectionFailed: "Could not open FTP data connection"
        }
    }
}

/// Minimal implicit-FTPS (port 990, TLS from the first byte) client — just
/// capable enough to list and download files from a Bambu Lab printer's SD
/// card over LAN.
///
/// Bambu printers only support *implicit* FTPS: the TLS handshake happens
/// immediately on connect, there's no `AUTH TLS` upgrade step. That rules out
/// Foundation/CFNetwork's old FTP APIs and most SPM FTP packages, which are
/// built for explicit FTPS or plain FTP. This is a from-scratch client using
/// Network.framework instead of a third-party dependency.
///
/// ⚠️ Not compiled or tested against a real printer yet — I have no Swift
/// toolchain or Bambu hardware in this environment. The biggest risk areas,
/// in order:
/// 1. `readReply` / `readLine` assume one `receive()` call returns exactly
///    one complete `\r\n`-terminated reply line. Real FTP servers can split
///    a reply across TCP segments, or (for multi-line replies like some
///    227/230 responses) send several lines under one reply code with a
///    `-` continuation marker. This client does not handle that — if you
///    see hangs or `unexpectedReply` errors, this is the first place to look.
/// 2. The TLS verify block unconditionally accepts the printer's
///    self-signed certificate, same trust model as the MQTT connection
///    elsewhere in this codebase.
/// 3. PASV data-channel encryption (`PROT P`) is assumed required; if Bambu's
///    FTPS server actually expects `PROT C` (cleartext data channel) LIST/RETR
///    will hang waiting for a TLS handshake that never comes.
public actor FTPSService {
    private var controlConnection: NWConnection?
    private let host: String
    private let accessCode: String
    private let port: UInt16 = 990

    public init(host: String, accessCode: String) {
        self.host = host
        self.accessCode = accessCode
    }

    public func connect() async throws {
        let connection = try makeTLSConnection(host: host, port: port)
        controlConnection = connection
        try await waitUntilReady(connection)

        _ = try await readReply(expecting: 220) // welcome banner
        try await sendCommand("USER bblp", expecting: 331)
        try await sendCommand("PASS \(accessCode)", expecting: 230)
        try await sendCommand("PBSZ 0", expecting: 200)
        try await sendCommand("PROT P", expecting: 200) // encrypt data channel too
        try await sendCommand("TYPE I", expecting: 200) // binary mode
        appLog(.info, category: logCategory, "FTPS session established with \(host)")
    }

    public func disconnect() {
        controlConnection?.cancel()
        controlConnection = nil
    }

    /// Lists files in a directory (non-recursive). `path` defaults to SD root.
    public func list(path: String = "/") async throws -> [FTPFileEntry] {
        let dataConnection = try await enterPassiveMode()
        try await sendCommand("LIST \(path)", expecting: 150)
        let raw = try await readAllData(from: dataConnection)
        _ = try await readReply(expecting: 226) // transfer complete
        let rawText = String(data: raw, encoding: .utf8) ?? "(non-UTF8 data, \(raw.count) bytes)"
        appLog(.info, category: logCategory, "Raw LIST response (\(raw.count) bytes): \(rawText.prefix(1000))")

        let parsed = Self.parseListing(raw)
        appLog(.info, category: logCategory, "Parsed \(parsed.count) entries: \(parsed.map { "\($0.name)[dir=\($0.isDirectory)]" })")
        return parsed
    }

    /// Downloads a whole file into memory. Bambu SD files (sliced
    /// .gcode.3mf projects) are typically a few MB — fine on a phone over
    /// LAN, but this is a full download with no resume/partial-read support.
    public func download(path: String) async throws -> Data {
        let dataConnection = try await enterPassiveMode()
        try await sendCommand("RETR \(path)", expecting: 150)
        let data = try await readAllData(from: dataConnection)
        _ = try await readReply(expecting: 226)
        return data
    }

    // MARK: - PASV / data connection

    private func enterPassiveMode() async throws -> NWConnection {
        let reply = try await sendCommand("PASV", expecting: 227)
        guard let (ip, dataPort) = Self.parsePASVReply(reply) else {
            throw FTPSError.unexpectedReply(reply)
        }
        let connection = try makeTLSConnection(host: ip, port: dataPort)
        do {
            try await waitUntilReady(connection)
        } catch {
            throw FTPSError.dataConnectionFailed
        }
        return connection
    }

    static func parsePASVReply(_ reply: String) -> (String, UInt16)? {
        // e.g. "227 Entering Passive Mode (192,168,1,50,204,130)."
        guard let open = reply.firstIndex(of: "("), let close = reply.firstIndex(of: ")") else { return nil }
        let numbers = reply[reply.index(after: open)..<close]
            .split(separator: ",")
            .compactMap { Int($0) }
        guard numbers.count == 6 else { return nil }
        let ip = "\(numbers[0]).\(numbers[1]).\(numbers[2]).\(numbers[3])"
        let port = UInt16(numbers[4] * 256 + numbers[5])
        return (ip, port)
    }

    // MARK: - Connection setup

    private func makeTLSConnection(host: String, port: UInt16) throws -> NWConnection {
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, _, complete in complete(true) }, // printer uses a self-signed cert
            DispatchQueue(label: "ftps.tls.verify")
        )
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw FTPSError.connectionFailed("invalid port \(port)")
        }
        let params = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        return NWConnection(host: .init(host), port: nwPort, using: params)
    }

    private func waitUntilReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [weak connection] state in
                switch state {
                case .ready:
                    connection?.stateUpdateHandler = nil
                    continuation.resume()
                case let .failed(error):
                    connection?.stateUpdateHandler = nil
                    continuation.resume(throwing: FTPSError.connectionFailed(error.localizedDescription))
                case .cancelled:
                    connection?.stateUpdateHandler = nil
                    continuation.resume(throwing: FTPSError.connectionFailed("cancelled"))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }


    // MARK: - Control connection I/O

    @discardableResult
    private func sendCommand(_ command: String, expecting code: Int) async throws -> String {
        guard let connection = controlConnection else {
            throw FTPSError.connectionFailed("not connected")
        }
        appLog(.info, category: logCategory, "-> \(command.hasPrefix("PASS") ? "PASS ****" : command)")
        try await send(command + "\r\n", on: connection)
        return try await readReply(expecting: code)
    }

    private func send(_ string: String, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: string.data(using: .utf8), completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func readReply(expecting code: Int) async throws -> String {
        guard let connection = controlConnection else {
            throw FTPSError.connectionFailed("not connected")
        }
        let line = try await readLine(from: connection)
        appLog(.info, category: logCategory, "<- \(line)")
        guard line.hasPrefix("\(code)") else {
            throw FTPSError.unexpectedReply(line)
        }
        return line
    }

    /// See the risk note in the type header: assumes one reply per receive().
    private func readLine(from connection: NWConnection) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let text = String(data: data, encoding: .utf8) else {
                    continuation.resume(throwing: FTPSError.unexpectedReply("(empty reply)"))
                    return
                }
                continuation.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    private func readAllData(from connection: NWConnection) async throws -> Data {
        defer { connection.cancel() }
        var collected = Data()
        while true {
            let (chunk, isComplete): (Data?, Bool) = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    continuation.resume(returning: (data, isComplete))
                }
            }
            if let chunk { collected.append(chunk) }
            if isComplete { break }
        }
        return collected
    }
    
    // MARK: - LIST parsing

    /// Parses a LIST response line by line, trying both listing styles
    /// embedded FTP servers commonly use — we don't know in advance which
    /// one Bambu's firmware returns:
    /// - Unix: "-rw-r--r-- 1 user group 1048576 Jan 01 12:00 model.gcode.3mf"
    /// - DOS/Windows: "08-27-26  10:30AM         5242880 model.gcode.3mf"
    ///   (or "<DIR>" instead of a size, for directories)
    static func parseListing(_ data: Data) -> [FTPFileEntry] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: { $0.isNewline }).compactMap { rawLine in
            let line = String(rawLine)
            guard !line.isEmpty else { return nil }
            return parseUnixLine(line) ?? parseDOSLine(line)
        }
    }

    private static func parseUnixLine(_ line: String) -> FTPFileEntry? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 9, let size = Int64(parts[4]) else { return nil }
        let isDirectory = parts[0].hasPrefix("d")
        let name = parts[8...].joined(separator: " ")
        return FTPFileEntry(name: name, sizeBytes: size, isDirectory: isDirectory)
    }

    private static func parseDOSLine(_ line: String) -> FTPFileEntry? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 4 else { return nil }
        let isDirectory = parts[2] == "<DIR>"
        let size = isDirectory ? 0 : (Int64(parts[2]) ?? -1)
        guard isDirectory || size >= 0 else { return nil }
        let name = parts[3...].joined(separator: " ")
        return FTPFileEntry(name: name, sizeBytes: size, isDirectory: isDirectory)
    }
}


    // 
