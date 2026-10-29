import Foundation

/// The app's languages; the same two as vomatt-web.
public enum Language: String, CaseIterable, Codable, Sendable {
    case en, zh

    /// What the API's `Accept-Language` and formatters expect.
    public var localeIdentifier: String { self == .zh ? "zh-TW" : "en" }

    /// The device's preferred language when it's one of ours, else English.
    public static func preferred(_ preferredLanguages: [String] = Locale.preferredLanguages) -> Language {
        for identifier in preferredLanguages {
            if identifier.hasPrefix("zh") { return .zh }
            if identifier.hasPrefix("en") { return .en }
        }
        return .en
    }
}

/// Looks up the web's `src/locales/{en,zh}.json` strings by dotted key, with
/// `{name}` placeholders, exactly like vomatt-web's `t()`. Strings the app adds
/// for iOS live in `ios.{en,zh}.json` and override the shared ones.
public struct Localizer: Sendable {
    public let language: Language
    private let strings: [String: String]
    private let fallback: [String: String]

    public init(language: Language, strings: [String: String], fallback: [String: String] = [:]) {
        self.language = language
        self.strings = strings
        self.fallback = fallback
    }

    /// Loads `<language>.json` and `ios.<language>.json` from `bundle`, English filling any gaps.
    public static func load(_ language: Language, bundle: Bundle) -> Localizer {
        func table(_ name: String) -> [String: String] {
            guard let url = bundle.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url)
            else { return [:] }
            return (try? flatten(json: data)) ?? [:]
        }
        let english = table("en").merging(table("ios.en")) { $1 }
        let strings = language == .en ? english : table(language.rawValue).merging(table("ios.\(language.rawValue)")) { $1 }
        return Localizer(language: language, strings: strings, fallback: english)
    }

    /// Flattens nested JSON objects into dotted keys: `{"poll":{"vote":"Vote"}}` -> `poll.vote`.
    public static func flatten(json data: Data) throws -> [String: String] {
        var result: [String: String] = [:]
        func walk(_ value: Any, path: String) {
            if let dict = value as? [String: Any] {
                for (key, child) in dict { walk(child, path: path.isEmpty ? key : "\(path).\(key)") }
            } else if let string = value as? String {
                result[path] = string
            }
        }
        walk(try JSONSerialization.jsonObject(with: data), path: "")
        return result
    }

    public func has(_ key: String) -> Bool { strings[key] != nil || fallback[key] != nil }

    /// The string for `key` with `{name}` placeholders filled in; the key itself when missing.
    public func callAsFunction(_ key: String, _ values: [String: CustomStringConvertible] = [:]) -> String {
        guard let template = strings[key] ?? fallback[key] else { return key }
        return Self.interpolate(template, values)
    }

    /// Replaces `{name}` placeholders; unknown ones stay as they are.
    public static func interpolate(_ template: String, _ values: [String: CustomStringConvertible]) -> String {
        guard !values.isEmpty, template.contains("{") else { return template }
        var output = ""
        var index = template.startIndex
        while index < template.endIndex {
            let char = template[index]
            if char == "{", let close = template[index...].firstIndex(of: "}") {
                let name = String(template[template.index(after: index)..<close])
                if let value = values[name], name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) {
                    output += value.description
                    index = template.index(after: close)
                    continue
                }
            }
            output.append(char)
            index = template.index(after: index)
        }
        return output
    }

    /// A "{count} …" string in the language's plural form: `key_one` for one where the language has
    /// that form (en), `key` otherwise, with the count grouped (1,200). From the web's `countText`.
    public func count(_ key: String, _ count: Int, _ values: [String: CustomStringConvertible] = [:]) -> String {
        let one = count == 1 && has("\(key)_one")
        return self(one ? "\(key)_one" : key, values.merging(["count": number(count)]) { _, new in new })
    }

    /// A number with grouping separators in this language: "1,234".
    public func number(_ value: Int) -> String {
        value.formatted(.number.locale(Locale(identifier: language.localeIdentifier)))
    }

    /// Sentences as one paragraph: a space between them in English, none after Chinese 。 (the web's `joinSentences`).
    public func sentences(_ sentences: String...) -> String {
        sentences.joined(separator: language == .zh ? "" : " ")
    }
}

public extension Localizer {
    /// Codes whose API message carries detail (which field, which value) the app's string drops.
    private static let detailedErrorCodes: Set<String> = ["common.bad_request", "common.validation_failed"]

    /// Codes shown with the app's own wording instead of the `apiError.*` copy (the web's `OVERRIDES`).
    private static let overrides = ["common.conflict": "common.busy"]

    /// What to show for a failed request: the app's override for its errorCode, else the `apiError.<errorCode>` string when there is one,
    /// else the API's own localized `message`, else `fallback`. A string that takes a value
    /// (`{0}`), or a detailed code, yields to the API's message, which carries that detail.
    func message(for error: Error, fallback: String) -> String {
        guard let error = error as? APIError else { return self(fallback) }
        // Only the API's answers carry a localized message; network and decoding failures don't
        let apiMessage = error.kind == .network || error.kind == .decoding ? nil : error.message
        if let code = error.errorCode, let key = Self.overrides[code] { return self(key) }
        if let code = error.errorCode, has("apiError.\(code)") {
            let text = self("apiError.\(code)")
            let takesValue = text.range(of: #"\{[A-Za-z0-9_-]+\}"#, options: .regularExpression) != nil
            guard takesValue || Self.detailedErrorCodes.contains(code) else { return text }
            return apiMessage ?? (takesValue ? self(fallback) : text)
        }
        return apiMessage ?? self(fallback)
    }
}
