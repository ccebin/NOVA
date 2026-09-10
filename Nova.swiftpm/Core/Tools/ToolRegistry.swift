import Foundation

public final class ToolRegistry: @unchecked Sendable {
    public static let shared = ToolRegistry()
    
    private let lock = NSLock()
    private var tools: [String: any NovaTool] = [:]
    
    public init() {}
    
    public func register(_ tool: any NovaTool) {
        lock.lock()
        defer { lock.unlock() }
        tools[tool.definition.id] = tool
    }
    
    public func tool(for id: String) -> (any NovaTool)? {
        lock.lock()
        defer { lock.unlock() }
        return tools[id]
    }
    
    public func allTools() -> [any NovaTool] {
        lock.lock()
        defer { lock.unlock() }
        return Array(tools.values)
    }
    
    public func allDefinitions() -> [ToolDefinition] {
        lock.lock()
        defer { lock.unlock() }
        return tools.values.map { $0.definition }
    }
    
    public func findTool(named name: String) -> (any NovaTool)? {
        lock.lock()
        defer { lock.unlock() }
        let lower = name.lowercased()
        return tools.values.first {
            $0.definition.id.lowercased() == lower ||
            $0.definition.name.lowercased() == lower
        }
    }
    
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        tools.removeAll()
    }
}
