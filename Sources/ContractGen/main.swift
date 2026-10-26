// Generates Sources/PortalKit/Generated.swift from the portal API contract.
//
//   swift run ContractGen sync <actions.json>   keep the actions in
//                                               contract/actions.txt, write
//                                               contract/portal.json, generate
//   swift run ContractGen generate              generate from contract/portal.json
//   swift run ContractGen check                 fail when Generated.swift is stale
//
// The contract is portal's contract/actions.json: each action with its input
// and output as JSON Schema and a hash. Outputs decode leniently where the
// portal may add things (unknown enum values, extra keys); everything the
// schema calls required must be there.
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let usedFile = root.appending(path: "contract/actions.txt")
let contractFile = root.appending(path: "contract/portal.json")
let generatedFile = root.appending(path: "Sources/PortalKit/Generated.swift")

typealias Schema = [String: Any]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func readJSON(_ url: URL) -> Any {
    guard let data = try? Data(contentsOf: url),
          let value = try? JSONSerialization.jsonObject(with: data)
    else { fail("cannot read \(url.path)") }
    return value
}

func usedActions() -> [String] {
    guard let text = try? String(contentsOf: usedFile, encoding: .utf8) else {
        fail("cannot read contract/actions.txt")
    }
    return text.split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
}

// MARK: - Names

let keywords: Set<String> = [
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import",
    "init", "inout", "internal", "let", "open", "operator", "private", "protocol", "public",
    "rethrows", "static", "struct", "subscript", "typealias", "var", "break", "case", "continue",
    "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat",
    "return", "switch", "where", "while", "as", "catch", "false", "is", "nil", "super", "self",
    "Self", "throw", "throws", "true", "try", "Type", "Protocol", "any", "some",
]
// Type names that would shadow what generated code uses.
let reservedTypes: Set<String> = [
    "String", "Int", "Double", "Bool", "Date", "Data", "Array", "Dictionary", "Optional",
    "Input", "Output", "Type", "Protocol", "Self", "JSONValue", "Decoder", "Encoder", "Error",
]

func words(_ s: String) -> [String] {
    var out: [String] = []
    var current = ""
    for ch in s {
        if ch == "_" || ch == "-" || ch == " " || ch == "." {
            if !current.isEmpty { out.append(current) }
            current = ""
        } else if ch.isUppercase, !current.isEmpty, current.last?.isLowercase == true {
            out.append(current)
            current = String(ch)
        } else {
            current.append(ch)
        }
    }
    if !current.isEmpty { out.append(current) }
    return out
}

func pascal(_ s: String) -> String {
    let name = words(s).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    let safe = name.first?.isNumber == true ? "N" + name : name
    return reservedTypes.contains(safe) ? safe + "Value" : safe
}

func camel(_ s: String) -> String {
    let p = words(s).enumerated().map { i, w in
        i == 0 ? w.prefix(1).lowercased() + w.dropFirst() : w.prefix(1).uppercased() + w.dropFirst()
    }.joined()
    let safe = p.first?.isNumber == true ? "_" + p : p
    return keywords.contains(safe) ? "`\(safe)`" : safe
}

func singular(_ s: String) -> String {
    if s.hasSuffix("ies") { return String(s.dropLast(3)) + "y" }
    for end in ["shes", "ches", "xes", "sses"] where s.hasSuffix(end) { return String(s.dropLast(2)) }
    if s.hasSuffix("s"), !s.hasSuffix("ss") { return String(s.dropLast()) }
    return s + "Item"
}

func quote(_ s: String) -> String {
    let escaped = s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}

// MARK: - Types

enum Side { case input, output }

/// One nested declaration scope: the type names used in it so siblings do
/// not collide.
final class Scope {
    var names: Set<String> = []
    var decls: [String] = []
    func claim(_ name: String) -> String {
        var candidate = name
        var n = 2
        while names.contains(candidate) {
            candidate = "\(name)\(n)"
            n += 1
        }
        names.insert(candidate)
        return candidate
    }
}

func indent(_ text: String, _ by: Int = 1) -> String {
    let pad = String(repeating: "    ", count: by)
    return text.split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.isEmpty ? "" : pad + $0 }.joined(separator: "\n")
}

/// Two schemas for the same value, merged: objects key by key, arrays item
/// by item, anything else as an anyOf (number or null becomes Double?).
func mergeSchemas(_ a: Schema, _ b: Schema) -> Schema {
    let ta = a["type"] as? String, tb = b["type"] as? String
    if ta == "object", tb == "object" { return mergeObjects([a, b]) }
    if ta == "array", tb == "array" {
        return ["type": "array", "items": mergeSchemas((a["items"] as? Schema) ?? [:], (b["items"] as? Schema) ?? [:])]
    }
    if NSDictionary(dictionary: a).isEqual(to: b) { return a }
    let parts = ((a["anyOf"] as? [Schema]) ?? [a]) + ((b["anyOf"] as? [Schema]) ?? [b])
    return ["anyOf": parts]
}

/// Objects in an anyOf merged into one: a key missing from some variant
/// becomes optional, and a key in several variants takes every shape.
func mergeObjects(_ variants: [Schema]) -> Schema {
    var properties: [String: Schema] = [:]
    var required: Set<String>?
    for v in variants {
        for (k, s) in (v["properties"] as? [String: Any]) ?? [:] {
            guard let s = s as? Schema else { continue }
            properties[k] = properties[k].map { mergeSchemas($0, s) } ?? s
        }
        let r = Set((v["required"] as? [String]) ?? [])
        required = required.map { $0.intersection(r) } ?? r
    }
    return ["type": "object", "properties": properties, "required": Array(required ?? []).sorted()]
}

/// The Swift type for a schema, declaring nested types in scope. Returns the
/// type and whether null is allowed.
func swiftType(_ schema: Schema, named: String, side: Side, scope: Scope) -> (String, Bool) {
    if let anyOf = schema["anyOf"] as? [Schema] {
        let nullable = anyOf.contains { ($0["type"] as? String) == "null" }
        let rest = anyOf.filter { ($0["type"] as? String) != "null" }
        if rest.count == 1 {
            let (t, inner) = swiftType(rest[0], named: named, side: side, scope: scope)
            return (t, nullable || inner)
        }
        // Same primitive twice (true and false, two enums): one of them.
        let kinds = Set(rest.compactMap { $0["type"] as? String })
        if kinds.count == 1, kinds.first == "boolean" { return ("Bool", nullable) }
        if !rest.isEmpty, rest.allSatisfy({ ($0["type"] as? String) == "object" }) {
            return (swiftType(mergeObjects(rest), named: named, side: side, scope: scope).0, nullable)
        }
        if !rest.isEmpty, rest.allSatisfy({ ($0["type"] as? String) == "number" || ($0["type"] as? String) == "integer" }) {
            return ("Double", nullable)
        }
        return ("JSONValue", nullable)
    }
    if let values = schema["enum"] as? [String] {
        let name = scope.claim(pascal(named))
        scope.decls.append(enumDecl(name, values, side: side))
        return (name, false)
    }
    switch schema["type"] as? String {
    case "string":
        if side == .output, schema["format"] as? String == "date-time" { return ("Date", false) }
        return ("String", false)
    case "integer": return ("Int", false)
    case "number": return ("Double", false)
    case "boolean": return ("Bool", false)
    case "null": return ("JSONValue", true)
    case "array":
        let items = (schema["items"] as? Schema) ?? [:]
        let (t, nullable) = swiftType(items, named: singular(named), side: side, scope: scope)
        return ("[\(nullable ? t + "?" : t)]", false)
    case "object":
        let properties = (schema["properties"] as? [String: Any]) ?? [:]
        if properties.isEmpty, let extra = schema["additionalProperties"] as? Schema, !extra.isEmpty {
            let (t, _) = swiftType(extra, named: named, side: side, scope: scope)
            return ("[String: \(t)]", false)
        }
        let name = scope.claim(pascal(named))
        scope.decls.append(structDecl(name, schema, side: side))
        return (name, false)
    default:
        return ("JSONValue", false)
    }
}

func enumDecl(_ name: String, _ values: [String], side: Side) -> String {
    var cases: [String] = []
    var used: Set<String> = []
    for v in values.sorted() {
        var c = camel(v.isEmpty ? "empty" : v)
        if c == "unknown" || used.contains(c) { c += "Value" }
        used.insert(c)
        cases.append(c == v || "`\(v)`" == c ? "case \(c)" : "case \(c) = \(quote(v))")
    }
    if side == .input {
        return """
        public enum \(name): String, Encodable, Sendable, Equatable, CaseIterable {
        \(indent(cases.joined(separator: "\n")))
        }
        """
    }
    // A value added on the portal side decodes as unknown instead of failing.
    return """
    public enum \(name): String, Decodable, Sendable, Equatable {
    \(indent(cases.joined(separator: "\n")))
        case unknown

        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Self(rawValue: raw) ?? .unknown
        }
    }
    """
}

func structDecl(_ name: String, _ schema: Schema, side: Side) -> String {
    let properties = (schema["properties"] as? [String: Any]) ?? [:]
    let required = Set((schema["required"] as? [String]) ?? [])
    let scope = Scope()
    var fields: [(key: String, swift: String, type: String, optional: Bool)] = []
    for key in properties.keys.sorted() {
        guard let s = properties[key] as? Schema else { continue }
        let (t, nullable) = swiftType(s, named: key, side: side, scope: scope)
        let optional = nullable || !required.contains(key)
        fields.append((key, camel(key), t, optional))
    }
    let conformance = side == .input ? "Encodable, Sendable, Equatable" : "Decodable, Sendable, Equatable"
    var body: [String] = fields.map { f in
        "public var \(f.swift): \(f.type)\(f.optional ? "?" : "")"
    }
    // Keys that are not valid Swift identifiers as written.
    if fields.contains(where: { $0.swift.trimmingCharacters(in: CharacterSet(charactersIn: "`")) != $0.key }) {
        let keys = fields.map { f in
            let bare = f.swift.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            return bare == f.key ? "case \(f.swift)" : "case \(f.swift) = \(quote(f.key))"
        }
        body.append("")
        body.append("enum CodingKeys: String, CodingKey {\n\(indent(keys.joined(separator: "\n")))\n}")
    }
    if side == .input {
        let params = fields.map { "\($0.swift): \($0.type)\($0.optional ? "? = nil" : "")" }
        let assigns = fields.map { f -> String in
            let bare = f.swift.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            return "self.\(bare) = \(f.swift)"
        }
        body.append("")
        body.append("public init(\(params.joined(separator: ", "))) {\n\(indent(assigns.joined(separator: "\n")))\n}")
    }
    if !scope.decls.isEmpty {
        body.append("")
        body.append(scope.decls.joined(separator: "\n\n"))
    }
    return """
    public struct \(name): \(conformance) {
    \(indent(body.joined(separator: "\n")))
    }
    """
}

func actionDecl(_ action: Schema) -> String {
    guard let name = action["name"] as? String,
          let app = action["app"] as? String,
          let hash = action["hash"] as? String,
          let title = action["title"] as? String
    else { fail("malformed action \(action["name"] ?? "?")") }
    let input = (action["input"] as? Schema) ?? [:]
    let output = (action["output"] as? Schema) ?? [:]

    // Input and Output are fixed names; their nested types get their own scope.
    let inputDecl = structDecl("Input", input, side: .input)
    let outputDecl: String
    if (output["type"] as? String) == "object", !((output["properties"] as? [String: Any]) ?? [:]).isEmpty {
        outputDecl = structDecl("Output", output, side: .output)
    } else {
        let scope = Scope()
        let (t, nullable) = swiftType(output, named: "Result", side: .output, scope: scope)
        outputDecl = (scope.decls + ["public typealias Output = \(t)\(nullable ? "?" : "")"]).joined(separator: "\n\n")
    }
    return """
    /// \(title)
    public enum \(pascal(name)): PortalAction {
        public static let name = \(quote(name))
        public static let app = \(quote(app))
        public static let hash = \(quote(hash))

    \(indent(inputDecl))

    \(indent(outputDecl))
    }
    """
}

func generate(_ actions: [Schema]) -> String {
    let sorted = actions.sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
    let table = sorted.map { a in
        "\(quote(a["name"] as! String)): (app: \(quote(a["app"] as! String)), hash: \(quote(a["hash"] as! String))),"
    }
    return """
    // Generated by `swift run ContractGen` from contract/portal.json. Do not edit.
    // swift-format-ignore-file
    import Foundation

    /// The actions this build was made against, with their contract hashes.
    public enum Contract {
        public static let actions: [String: (app: String, hash: String)] = [
    \(indent(table.joined(separator: "\n"), 2))
        ]
    }

    \(sorted.map(actionDecl).joined(separator: "\n\n"))

    """
}

// MARK: - Commands

func pretty(_ value: Any) -> Data {
    guard let data = try? JSONSerialization.data(
        withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    ) else { fail("cannot encode JSON") }
    return data + Data("\n".utf8)
}

func contractActions() -> [Schema] {
    guard let actions = readJSON(contractFile) as? [Schema] else { fail("contract/portal.json is not a list") }
    return actions
}

func write(_ text: String, to url: URL) {
    do { try Data(text.utf8).write(to: url) } catch { fail("cannot write \(url.path): \(error)") }
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "sync":
    guard let source = args.dropFirst().first else { fail("usage: ContractGen sync <actions.json>") }
    guard let all = readJSON(URL(fileURLWithPath: source)) as? [Schema] else { fail("\(source) is not a list") }
    let byName = Dictionary(all.map { ($0["name"] as? String ?? "", $0) }, uniquingKeysWith: { a, _ in a })
    var kept: [Schema] = []
    for name in usedActions() {
        guard let action = byName[name] else { fail("\(name): not in the portal contract (removed or renamed?)") }
        kept.append(action)
    }
    do { try pretty(kept).write(to: contractFile) } catch { fail("cannot write contract/portal.json") }
    write(generate(kept), to: generatedFile)
    print("contract/portal.json: \(kept.count) actions")
case "generate":
    write(generate(contractActions()), to: generatedFile)
    print("Sources/PortalKit/Generated.swift written")
case "check":
    let actions = contractActions()
    let names = Set(actions.compactMap { $0["name"] as? String })
    for name in usedActions() where !names.contains(name) {
        fail("\(name): in contract/actions.txt but not in contract/portal.json; run scripts/sync-contract.sh")
    }
    let current = (try? String(contentsOf: generatedFile, encoding: .utf8)) ?? ""
    if current != generate(actions) { fail("Generated.swift is stale; run swift run ContractGen generate") }
    print("Generated.swift: up to date")
default:
    fail("usage: ContractGen sync <actions.json> | generate | check")
}
