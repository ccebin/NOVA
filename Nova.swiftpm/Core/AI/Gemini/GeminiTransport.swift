import Foundation

/// HTTP transport protocol for Gemini REST API calls.
public protocol GeminiHTTPTransport: Sendable {
    func send(request: URLRequest) async throws -> (Data, HTTPURLResponse)
    func stream(request: URLRequest) -> AsyncThrowingStream<Data, Error>
}

/// WebSocket transport protocol for Gemini Live bidirectional streaming.
public protocol GeminiWebSocketTransport: Sendable {
    func connect(url: URL, headers: [String: String]) async throws
    func send(message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
    func disconnect()
    var isConnected: Bool { get }
}

/// Production implementation of HTTP transport using URLSession.
public final class URLSessionGeminiTransport: GeminiHTTPTransport, Sendable {
    private let session: URLSession
    
    public init(session: URLSession = .shared) {
        self.session = session
    }
    
    public func send(request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIProviderError.serviceUnavailable("Invalid non-HTTP response received from Gemini server.")
            }
            return (data, httpResponse)
        } catch let err as URLError where err.code == .notConnectedToInternet || err.code == .networkConnectionLost || err.code == .timedOut {
            throw AIProviderError.networkUnavailable("Internet connection unavailable: \(err.localizedDescription)")
        } catch {
            throw error
        }
    }
    
    public func stream(request: URLRequest) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (asyncBytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AIProviderError.serviceUnavailable("Invalid response"))
                        return
                    }
                    
                    if httpResponse.statusCode == 429 {
                        continuation.finish(throwing: AIProviderError.quotaExceeded("Gemini Free Tier rate limit exceeded (HTTP 429)."))
                        return
                    }
                    
                    guard (200...299).contains(httpResponse.statusCode) else {
                        continuation.finish(throwing: AIProviderError.serviceUnavailable("Gemini returned HTTP \(httpResponse.statusCode)."))
                        return
                    }
                    
                    var lineBuffer = Data()
                    for try await byte in asyncBytes {
                        try Task.checkCancellation()
                        if byte == 10 { // Newline '\n'
                            if !lineBuffer.isEmpty {
                                continuation.yield(lineBuffer)
                                lineBuffer = Data()
                            }
                        } else {
                            lineBuffer.append(byte)
                        }
                    }
                    if !lineBuffer.isEmpty {
                        continuation.yield(lineBuffer)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: AIProviderError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

/// Production implementation of WebSocket transport for Gemini Live using URLSession.
public final class URLSessionWebSocketGeminiTransport: NSObject, GeminiWebSocketTransport, @unchecked Sendable {
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let lock = NSLock()
    private var _isConnected: Bool = false
    
    public override init() {
        super.init()
    }
    
    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isConnected
    }
    
    public func connect(url: URL, headers: [String: String]) async throws {
        lock.lock()
        var request = URLRequest(url: url)
        for (header, value) in headers {
            request.setValue(value, forHTTPHeaderField: header)
        }
        
        let session = URLSession(configuration: .default)
        self.urlSession = session
        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        self._isConnected = true
        lock.unlock()
        
        task.resume()
    }
    
    public func send(message: URLSessionWebSocketTask.Message) async throws {
        lock.lock()
        let task = self.webSocketTask
        lock.unlock()
        
        guard let task = task else {
            throw AIProviderError.serviceUnavailable("WebSocket task is not connected.")
        }
        try await task.send(message)
    }
    
    public func receive() async throws -> URLSessionWebSocketTask.Message {
        lock.lock()
        let task = self.webSocketTask
        lock.unlock()
        
        guard let task = task else {
            throw AIProviderError.serviceUnavailable("WebSocket task is not connected.")
        }
        return try await task.receive()
    }
    
    public func disconnect() {
        lock.lock()
        defer { lock.unlock() }
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        _isConnected = false
    }
}

/// Deterministic Mock HTTP Transport for Unit Tests and Offline Diagnostics.
public final class MockGeminiHTTPTransport: GeminiHTTPTransport, @unchecked Sendable {
    public typealias Handler = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    
    private var handler: Handler?
    private let lock = NSLock()
    
    public init(handler: Handler? = nil) {
        self.handler = handler
    }
    
    public func setHandler(_ newHandler: @escaping Handler) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = newHandler
    }
    
    public func send(request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock()
        let h = self.handler
        lock.unlock()
        
        if let h = h {
            return try await h(request)
        }
        
        // Default mock success response
        let json = """
        {
          "candidates": [
            {
              "content": {
                "parts": [
                  { "text": "Mock Gemini response from pure Swift deterministic transport." }
                ],
                "role": "model"
              },
              "finishReason": "STOP"
            }
          ]
        }
        """
        let data = json.data(using: .utf8)!
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (data, response)
    }
    
    public func stream(request: URLRequest) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let (data, response) = try await self.send(request: request)
                    if response.statusCode == 429 {
                        continuation.finish(throwing: AIProviderError.quotaExceeded("Mock quota exceeded (HTTP 429)"))
                        return
                    }
                    continuation.yield(data)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

/// Deterministic Mock WebSocket Transport for testing Gemini Live connection lifecycles.
public final class MockGeminiWebSocketTransport: GeminiWebSocketTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _isConnected: Bool = false
    public private(set) var sentMessages: [URLSessionWebSocketTask.Message] = []
    public var incomingMessages: [URLSessionWebSocketTask.Message] = []
    
    public init() {}
    
    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isConnected
    }
    
    public func connect(url: URL, headers: [String: String]) async throws {
        lock.lock()
        defer { lock.unlock() }
        _isConnected = true
    }
    
    public func send(message: URLSessionWebSocketTask.Message) async throws {
        lock.lock()
        defer { lock.unlock() }
        sentMessages.append(message)
    }
    
    public func receive() async throws -> URLSessionWebSocketTask.Message {
        lock.lock()
        defer { lock.unlock() }
        guard !incomingMessages.isEmpty else {
            // Return a default setupComplete if queue empty
            let json = "{\"setupComplete\":{}}"
            return .string(json)
        }
        return incomingMessages.removeFirst()
    }
    
    public func queueIncoming(message: URLSessionWebSocketTask.Message) {
        lock.lock()
        defer { lock.unlock() }
        incomingMessages.append(message)
    }
    
    public func disconnect() {
        lock.lock()
        defer { lock.unlock() }
        _isConnected = false
    }
}
