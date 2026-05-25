import Foundation

nonisolated enum CSVEncoder {
    static func row(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",")
    }

    static func field(_ value: String) -> String {
        let formulaSafeValue = neutralizeFormulaPrefix(value)
        let needsQuotes = formulaSafeValue.contains("\"") ||
            formulaSafeValue.contains(",") ||
            formulaSafeValue.contains("\n") ||
            formulaSafeValue.contains("\r")

        guard needsQuotes else {
            return formulaSafeValue
        }

        let escaped = formulaSafeValue.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func neutralizeFormulaPrefix(_ value: String) -> String {
        guard let firstNonWhitespace = value.first(where: { !$0.isWhitespace }) else {
            return value
        }

        if ["=", "+", "-", "@"].contains(firstNonWhitespace) {
            return "'\(value)"
        }

        return value
    }
}
