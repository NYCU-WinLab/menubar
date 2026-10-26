import Foundation

/// The portal's change stream (GET /api/events with the API key): one action
/// name per change in the key's apps. Reconnects with backoff until the task
/// is cancelled; a refused key ends it.
public struct ChangeStream: Sendable {
    public enum Event: Sendable, Equatable {
        /// Connected; anything may have changed while we were away.
        case connected
        case change(String)
        case disconnected
    }

    let client: PortalClient

    public init(client: PortalClient) {
        self.client = client
    }

    public func events() -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var delay: Duration = .seconds(1)
                while !Task.isCancelled {
                    do {
                        var request = try client.request("api/events", method: "GET")
                        request.timeoutInterval = 90 // pings come every 25 s
                        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        let (bytes, response) = try await client.session.bytes(for: request)
                        guard let http = response as? HTTPURLResponse else { throw PortalError.unavailable("no response") }
                        switch http.statusCode {
                        case 200: break
                        case 401, 403: throw PortalError.unauthorized("\(http.statusCode)")
                        default: throw PortalError.unavailable("\(http.statusCode)")
                        }
                        continuation.yield(.connected)
                        delay = .seconds(1)
                        for try await line in bytes.lines {
                            if let name = Self.parse(line) { continuation.yield(.change(name)) }
                        }
                        continuation.yield(.disconnected)
                    } catch let error as PortalError {
                        if case .unavailable = error {
                            continuation.yield(.disconnected)
                        } else {
                            continuation.finish(throwing: error)
                            return
                        }
                    } catch {
                        if Task.isCancelled { break }
                        continuation.yield(.disconnected)
                    }
                    try? await Task.sleep(for: delay)
                    delay = min(delay * 2, .seconds(60))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The action name in a `data:` line; nil for comments, retry and blanks.
    static func parse(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let value = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}
