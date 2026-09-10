import Foundation

public enum GenericToolRouter {
    /// Domain-agnostic matcher that queries tool definitions in the registry
    /// and dynamically extracts arguments based on the tool's argument schema.
    public static func matchAndExtract(
        prompt: String,
        from registry: ToolRegistry
    ) -> (tool: any NovaTool, arguments: ToolArguments)? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let allTools = registry.allTools()
        
        // 1. Explicit tool invocation syntax: e.g. "tool: Create Reminder title: Buy milk"
        for tool in allTools {
            let def = tool.definition
            let nameLower = def.name.lowercased()
            let idLower = def.id.lowercased()
            
            if trimmed.lowercased().hasPrefix("tool: \(nameLower)") ||
               trimmed.lowercased().hasPrefix("tool: \(idLower)") ||
               trimmed.lowercased().hasPrefix("/tool \(idLower)") ||
               trimmed.lowercased().hasPrefix("/tool \(nameLower)") {
                let args = extractArguments(from: trimmed, schema: def.arguments)
                return (tool, args)
            }
        }
        
        // 2. Generic intent matching against registered tool definitions (Zero hardcoding)
        for tool in allTools {
            let def = tool.definition
            let nameWords = def.name.lowercased().components(separatedBy: .whitespaces)
            let promptLower = trimmed.lowercased()
            
            // Check if user prompt contains the core verb/noun of the tool definition
            let matchesName = nameWords.allSatisfy { promptLower.contains($0) }
            
            if matchesName {
                let args = extractArguments(from: trimmed, schema: def.arguments)
                return (tool, args)
            }
        }
        
        return nil
    }
    
    private static func extractArguments(from prompt: String, schema: [ToolArgumentDefinition]) -> ToolArguments {
        var dict: [String: String] = [:]
        
        // Strategy A: Explicit key: "value" or key=value parsing
        for arg in schema {
            // Pattern 1: key: "value" or key: value
            if let range = prompt.range(of: "\(arg.name):", options: .caseInsensitive) {
                let remainder = String(prompt[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                let value = extractValue(from: remainder)
                if !value.isEmpty {
                    dict[arg.name] = value
                }
            } else if let range = prompt.range(of: "\(arg.name)=", options: .caseInsensitive) {
                let remainder = String(prompt[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                let value = extractValue(from: remainder)
                if !value.isEmpty {
                    dict[arg.name] = value
                }
            }
        }
        
        // Strategy B: Fallback for single required string argument if not explicitly tagged
        if dict.isEmpty {
            let requiredArgs = schema.filter { $0.isRequired }
            if requiredArgs.count == 1, let primary = requiredArgs.first, primary.typeDescription == "string" {
                // Extract everything after common trigger words as the title/content
                var content = prompt
                let triggers = ["create", "add", "new", "schedule", "remind me to", "remind me"]
                for trig in triggers {
                    if let range = content.range(of: trig, options: .caseInsensitive) {
                        content = String(content[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                        break
                    }
                }
                if !content.isEmpty {
                    dict[primary.name] = content
                }
            }
        }
        
        return ToolArguments(dict)
    }
    
    private static func extractValue(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("\"") {
            let withoutLeading = String(trimmed.dropFirst())
            if let closingQuote = withoutLeading.firstIndex(of: "\"") {
                return String(withoutLeading[..<closingQuote])
            }
        }
        
        // Take up to next argument delimiter or end of string
        let parts = trimmed.components(separatedBy: .whitespaces)
        var resultWords: [String] = []
        for word in parts {
            if word.contains(":") && !word.hasPrefix("http") {
                break
            }
            resultWords.append(word)
        }
        return resultWords.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "\", "))
    }
}
