import Foundation

/// A portal action as generated from the contract: its name, the API app it
/// belongs to, the contract hash this build was made against, and its types.
public protocol PortalAction {
    associatedtype Input: Encodable & Sendable
    associatedtype Output: Decodable & Sendable
    static var name: String { get }
    static var app: String { get }
    static var hash: String { get }
}

public enum PortalError: Error, Equatable, LocalizedError {
    /// No API key saved yet.
    case noKey
    /// The key is wrong, revoked, or its owner left the lab (401, 403).
    case unauthorized(String)
    /// The key exists but is not allowed into this action's app.
    case forbidden(String)
    /// The action said no (400), with the portal's message.
    case refused(String)
    /// Too many calls; retry after the given seconds.
    case rateLimited(Int?)
    /// The answer did not match the contract this build knows.
    case contract(action: String, detail: String)
    /// Network or server trouble.
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .noKey: "還沒設定 API 金鑰"
        case let .unauthorized(m): "金鑰無效：\(m)"
        case let .forbidden(m): "金鑰沒有這個權限：\(m)"
        case let .refused(m): m
        case let .rateLimited(s): s.map { "太頻繁了，\($0) 秒後再試" } ?? "太頻繁了，稍後再試"
        case let .contract(action, _): "portal 的 \(action) 已更新，請更新 WinLab"
        case let .unavailable(m): "連不到 portal：\(m)"
        }
    }
}

/// One entry of GET /api/actions.
public struct RemoteAction: Decodable, Sendable, Equatable {
    public let name: String
    public let app: String?
    public let hash: String?
}

/// Calls portal actions with an API key: POST /api/actions/<name>.
public struct PortalClient: Sendable {
    public let baseURL: URL
    public let key: @Sendable () -> String?
    let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared, key: @escaping @Sendable () -> String?) {
        self.baseURL = baseURL
        self.session = session
        self.key = key
    }

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = parseDate(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a date: \(text)"))
        }
        return decoder
    }()

    /// ISO 8601 as JSON.stringify writes it, with or without milliseconds.
    public static func parseDate(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        return try? Date(text, strategy: .iso8601)
    }

    func request(_ path: String, method: String, body: Data? = nil) throws -> URLRequest {
        guard let key = key(), !key.isEmpty else { throw PortalError.noKey }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("WinLab-Mac/\(Bundle.main.appVersion)", forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.timeoutInterval = 20
        return request
    }

    public func run<A: PortalAction>(_: A.Type, _ input: A.Input) async throws -> A.Output {
        let body = try JSONEncoder().encode(input)
        let data = try await send(request("api/actions/\(A.name)", method: "POST", body: body))
        do {
            return try Self.decoder.decode(A.Output.self, from: data)
        } catch {
            throw PortalError.contract(action: A.name, detail: String(describing: error))
        }
    }

    /// What this key can call, with each action's contract hash.
    public func actions() async throws -> [RemoteAction] {
        struct List: Decodable { let actions: [RemoteAction] }
        let data = try await send(request("api/actions", method: "GET"))
        do {
            return try JSONDecoder().decode(List.self, from: data).actions
        } catch {
            throw PortalError.contract(action: "actions", detail: String(describing: error))
        }
    }

    func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PortalError.unavailable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw PortalError.unavailable("no HTTP response") }
        if (200 ..< 300).contains(http.statusCode) { return data }
        let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
        switch http.statusCode {
        case 400: throw PortalError.refused(message)
        case 401: throw PortalError.unauthorized(message)
        case 403 where message.contains("not allowed into") || message.contains("cannot be called"):
            throw PortalError.forbidden(message)
        case 403: throw PortalError.unauthorized(message)
        case 404: throw PortalError.contract(action: request.url?.lastPathComponent ?? "?", detail: message)
        case 429: throw PortalError.rateLimited(http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init))
        default: throw PortalError.unavailable("\(http.statusCode) \(message)")
        }
    }
}

/// How the actions this build uses compare with what the portal serves now.
public struct ContractStatus: Sendable, Equatable {
    /// Used actions the key cannot call (app not granted, or removed).
    public var missing: [String] = []
    /// Used actions whose schema changed since this build.
    public var changed: [String] = []

    public init(remote: [RemoteAction], used: [String: (app: String, hash: String)] = Contract.actions) {
        let byName = Dictionary(remote.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for (name, info) in used.sorted(by: { $0.key < $1.key }) {
            guard let r = byName[name] else {
                missing.append(name)
                continue
            }
            if let hash = r.hash, hash != info.hash { changed.append(name) }
        }
    }

    public static func == (a: Self, b: Self) -> Bool { a.missing == b.missing && a.changed == b.changed }
}

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
