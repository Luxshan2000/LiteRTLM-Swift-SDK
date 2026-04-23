import Foundation
import LiteRTLM

/// Sample tools that demonstrate LiteRTLM's tool-calling capability.
enum SampleTools {

    /// All available demo tools.
    static let all: [Tool] = [weather, calculator, diceRoll]

    // MARK: - Weather

    static let weather = Tool(
        name: "get_weather",
        description: "Get the current weather for a city. Returns temperature, condition, and humidity.",
        parameters: [
            .init(name: "city", type: .string, description: "City name (e.g. Tokyo, London)", required: true),
            .init(name: "unit", type: .string, description: "Temperature unit: celsius or fahrenheit"),
        ]
    ) { args in
        let city = args["city"] as? String ?? "Unknown"
        let unit = (args["unit"] as? String ?? "celsius").lowercased()

        // Simulated weather data
        let conditions = ["sunny", "partly cloudy", "cloudy", "rainy", "windy"]
        let condition = conditions[abs(city.hashValue) % conditions.count]
        let tempC = 15 + abs(city.hashValue) % 20
        let temp = unit == "fahrenheit" ? Int(Double(tempC) * 1.8 + 32) : tempC
        let humidity = 40 + abs(city.hashValue) % 50

        return [
            "city": city,
            "temperature": temp,
            "unit": unit == "fahrenheit" ? "°F" : "°C",
            "condition": condition,
            "humidity": "\(humidity)%",
        ]
    }

    // MARK: - Calculator

    static let calculator = Tool(
        name: "calculate",
        description: "Evaluate a basic math expression. Supports +, -, *, / operations.",
        parameters: [
            .init(name: "expression", type: .string, description: "Math expression (e.g. '24 * 365')", required: true),
        ]
    ) { args in
        let expr = args["expression"] as? String ?? ""
        let expression = NSExpression(format: expr)
        if let result = expression.expressionValue(with: nil, context: nil) as? NSNumber {
            return ["expression": expr, "result": result.doubleValue]
        }
        return ["expression": expr, "error": "Could not evaluate"]
    }

    // MARK: - Dice Roll

    static let diceRoll = Tool(
        name: "roll_dice",
        description: "Roll one or more dice and return the results.",
        parameters: [
            .init(name: "count", type: .integer, description: "Number of dice to roll (default 1)"),
            .init(name: "sides", type: .integer, description: "Number of sides per die (default 6)"),
        ]
    ) { args in
        let count = min((args["count"] as? Int) ?? 1, 20)
        let sides = max((args["sides"] as? Int) ?? 6, 2)
        let rolls = (0..<max(count, 1)).map { _ in Int.random(in: 1...sides) }
        return [
            "rolls": rolls,
            "total": rolls.reduce(0, +),
            "dice": "\(count)d\(sides)",
        ]
    }
}
