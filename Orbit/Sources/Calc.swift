import Foundation

/// Безопасный калькулятор (свой парсер, без NSExpression — тот падает на кривом вводе)
struct Calc {
    private let s: [Character]; private var i = 0
    static func eval(_ text: String) -> Double? {
        let t = text.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/").replacingOccurrences(of: " ", with: "")
        guard !t.isEmpty, t.contains(where: { "+-*/^%()".contains($0) }) || t.lowercased().hasPrefix("sqrt"),
              t.allSatisfy({ "0123456789.+-*/^%()sqrtpie".contains($0) }) else { return nil }
        var c = Calc(s: Array(t))
        guard let v = c.expr(), c.i == c.s.count, v.isFinite else { return nil }
        return v
    }
    private init(s: [Character]) { self.s = s }
    private var peek: Character? { i < s.count ? s[i] : nil }
    private mutating func expr() -> Double? {
        guard var v = term() else { return nil }
        while let c = peek, c == "+" || c == "-" { i += 1; guard let r = term() else { return nil }; v = c == "+" ? v + r : v - r }
        return v
    }
    private mutating func term() -> Double? {
        guard var v = power() else { return nil }
        while let c = peek, c == "*" || c == "/" || c == "%" {
            i += 1; guard let r = power() else { return nil }
            v = c == "*" ? v * r : c == "/" ? v / r : v.truncatingRemainder(dividingBy: r)
        }
        return v
    }
    private mutating func power() -> Double? {
        guard let b = unary() else { return nil }
        if peek == "^" { i += 1; guard let e = power() else { return nil }; return pow(b, e) }
        return b
    }
    private mutating func unary() -> Double? {
        if peek == "-" { i += 1; return unary().map { -$0 } }
        if peek == "+" { i += 1; return unary() }
        return atom()
    }
    private mutating func atom() -> Double? {
        if peek == "(" { i += 1; let v = expr(); guard peek == ")" else { return nil }; i += 1; return v }
        if String(s[i...]).hasPrefix("sqrt") { i += 4; return atom().map { $0.squareRoot() } }
        if String(s[i...]).hasPrefix("pi") { i += 2; return .pi }
        if peek == "e" { i += 1; return M_E }
        let st = i
        while let c = peek, c.isNumber || c == "." { i += 1 }
        return st == i ? nil : Double(String(s[st..<i]))
    }
    static func format(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        let f = NumberFormatter(); f.maximumFractionDigits = 8; f.decimalSeparator = "."; f.usesGroupingSeparator = false
        return f.string(from: v as NSNumber) ?? "\(v)"
    }
}
