import Foundation

/// A tool (function) that the model can call during generation.
///
/// ```swift
/// let weatherTool = Tool(
///     name: "get_weather",
///     description: "Get current weather for a city",
///     parameters: [
///         .init(name: "city", type: .string, description: "City name", required: true),
///         .init(name: "unit", type: .string, description: "celsius or fahrenheit")
///     ]
/// ) { args in
///     let city = args["city"] as? String ?? "unknown"
///     return ["temperature": 22, "city": city, "unit": "celsius"]
/// }
/// ```
public struct Tool: Sendable {

    /// Tool name (must match what the model outputs).
    public let name: String

    /// Human-readable description for the model.
    public let description: String

    /// Parameter definitions.
    public let parameters: [Parameter]

    /// The function to execute when the model calls this tool.
    /// Receives a dictionary of argument name → value, returns a result dictionary.
    public let execute: @Sendable ([String: Any]) async throws -> [String: Any]

    public init(
        name: String,
        description: String,
        parameters: [Parameter] = [],
        execute: @escaping @Sendable ([String: Any]) async throws -> [String: Any]
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.execute = execute
    }

    // MARK: - Parameter Definition

    public struct Parameter: Sendable {
        public let name: String
        public let type: ParameterType
        public let description: String
        public let required: Bool

        public init(
            name: String,
            type: ParameterType = .string,
            description: String = "",
            required: Bool = false
        ) {
            self.name = name
            self.type = type
            self.description = description
            self.required = required
        }
    }

    public enum ParameterType: String, Sendable {
        case string
        case number
        case integer
        case boolean
        case array
        case object
    }

    // MARK: - JSON Schema

    /// Generate OpenAPI-compatible JSON schema for this tool.
    func toJSONSchema() -> [String: Any] {
        var properties: [String: Any] = [:]
        var requiredParams: [String] = []

        for param in parameters {
            var prop: [String: Any] = ["type": param.type.rawValue]
            if !param.description.isEmpty {
                prop["description"] = param.description
            }
            properties[param.name] = prop
            if param.required {
                requiredParams.append(param.name)
            }
        }

        let schema: [String: Any] = [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": requiredParams,
                ] as [String: Any],
            ] as [String: Any],
        ]

        return schema
    }
}

/// Result from a tool execution, fed back to the model.
public struct ToolResult: @unchecked Sendable {
    public let toolName: String
    public let result: [String: Any]

    public init(toolName: String, result: [String: Any]) {
        self.toolName = toolName
        self.result = result
    }
}
