// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Case matters: `MM` is the month and `mm` the minute.
enum NotchDateToken: String, CaseIterable {
    case weekdayName = "DDDD", weekdayShort = "DDD", dayPadded = "DD", day = "D"
    case monthName = "MMMM", monthShort = "MMM", monthPadded = "MM", month = "M"
    case year = "YYYY", yearShort = "YY"
    case hourPadded = "HH", hour = "H", hour12Padded = "hh", hour12 = "h"
    case minute = "mm", period = "A"

    /// `DDDD` must be tried before `DD`, or it would read as two days.
    fileprivate static let longestFirst = allCases.sorted { $0.rawValue.count > $1.rawValue.count }

    fileprivate var isClock: Bool {
        switch self {
        case .hourPadded, .hour, .hour12Padded, .hour12, .minute, .period: return true
        default: return false
        }
    }

    /// Typical rendered length, used only to balance the two wings.
    fileprivate var nominalLength: Int {
        switch self {
        case .weekdayName, .monthName: return 8
        case .weekdayShort, .monthShort: return 3
        case .year: return 4
        default: return 2
        }
    }

    fileprivate func value(_ parts: DateComponents, calendar: Calendar) -> String {
        func name(_ symbols: [String], _ index: Int?) -> String {
            guard let index, symbols.indices.contains(index - 1) else { return "" }
            return symbols[index - 1]
        }
        func padded(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
        let hour = parts.hour ?? 0
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        switch self {
        case .weekdayName: return name(calendar.weekdaySymbols, parts.weekday)
        case .weekdayShort: return name(calendar.shortWeekdaySymbols, parts.weekday)
        case .dayPadded: return padded(parts.day)
        case .day: return String(parts.day ?? 0)
        case .monthName: return name(calendar.monthSymbols, parts.month)
        case .monthShort: return name(calendar.shortMonthSymbols, parts.month)
        case .monthPadded: return padded(parts.month)
        case .month: return String(parts.month ?? 0)
        case .year: return String(parts.year ?? 0)
        case .yearShort: return padded((parts.year ?? 0) % 100)
        case .hourPadded: return padded(hour)
        case .hour: return String(hour)
        case .hour12Padded: return padded(hour12)
        case .hour12: return String(hour12)
        case .minute: return padded(parts.minute)
        case .period: return hour < 12 ? calendar.amSymbol : calendar.pmSymbol
        }
    }

    /// Everything this token can ever show. Digits are drawn monospaced, so
    /// one two-digit value stands for all of them.
    fileprivate func candidates(calendar: Calendar) -> [String] {
        switch self {
        case .weekdayName: return calendar.weekdaySymbols
        case .weekdayShort: return calendar.shortWeekdaySymbols
        case .monthName: return calendar.monthSymbols
        case .monthShort: return calendar.shortMonthSymbols
        case .period: return [calendar.amSymbol, calendar.pmSymbol]
        case .year: return ["0000"]
        default: return ["00"]
        }
    }
}

struct NotchDateText: Equatable {
    let leading: String
    let trailing: String
}

/// A typed pattern such as `DDDD DD/MM/YYYY`, already divided between the
/// wings on either side of the camera.
struct NotchDatePattern: Equatable {
    /// Divides the wings explicitly: `DDDD | DD/MM/YYYY`.
    static let separator: Character = "|"

    fileprivate enum Atom: Equatable {
        case token(NotchDateToken)
        /// Bracketed text is shown exactly as written, so it is never a place
        /// to divide the wings and never trimmed from their edges.
        case literal(Character, bracketed: Bool)

        var nominalLength: Int {
            if case .token(let token) = self { return token.nominalLength }
            return 1
        }
        /// Spaces and list punctuation mean nothing beside the camera.
        var isTrimmable: Bool {
            if case .literal(let character, false) = self { return character.isWhitespace || character == "," || character == ";" }
            return false
        }
        var isSpace: Bool {
            if case .literal(let character, false) = self { return character.isWhitespace }
            return false
        }
    }

    private let leading: [Atom]
    private let trailing: [Atom]
    /// The same date in one piece, for places no camera divides.
    private let whole: [Atom]

    var isEmpty: Bool { leading.isEmpty && trailing.isEmpty }
    /// Without a clock, the text changes once a day.
    var showsTime: Bool {
        (leading + trailing).contains { if case .token(let token) = $0 { return token.isClock } else { return false } }
    }

    init(_ raw: String) {
        var atoms: [Atom] = []
        var cut: Int?
        var escaped = false
        var rest = Substring(raw)
        while let character = rest.first {
            if escaped {
                rest.removeFirst()
                if character == "]" { escaped = false } else { atoms.append(.literal(character, bracketed: true)) }
            } else if character == "[" {
                rest.removeFirst()
                escaped = true
            } else if character == Self.separator, cut == nil {
                rest.removeFirst()
                cut = atoms.count
            } else if let token = NotchDateToken.longestFirst.first(where: { rest.hasPrefix($0.rawValue) }) {
                rest.removeFirst(token.rawValue.count)
                atoms.append(.token(token))
            } else {
                rest.removeFirst()
                atoms.append(.literal(character, bracketed: false))
            }
        }
        let halves: ([Atom], [Atom])
        if let cut {
            halves = (Array(atoms[..<cut]), Array(atoms[cut...]))
        } else if let space = Self.balancedSpace(in: atoms) {
            halves = (Array(atoms[..<space]), Array(atoms[(space + 1)...]))
        } else {
            halves = ([], atoms)
        }
        let first = Self.trimmed(halves.0), second = Self.trimmed(halves.1)
        // One filled half always sits opposite the calendar symbol.
        (leading, trailing) = second.isEmpty ? ([], first) : (first, second)
        // A typed separator leaves a space behind; a chosen space keeps what surrounded it.
        whole = cut == nil ? Self.trimmed(atoms)
            : first + (first.isEmpty || second.isEmpty ? [] : [.literal(" ", bracketed: false)]) + second
    }

    /// The division is chosen from the pattern, never from a rendered date, so
    /// it cannot move between a short weekday and a long one.
    private static func balancedSpace(in atoms: [Atom]) -> Int? {
        let total = atoms.reduce(0) { $0 + $1.nominalLength }
        var before = 0
        var best: (index: Int, imbalance: Int)?
        for (index, atom) in atoms.enumerated() {
            if atom.isSpace {
                let imbalance = abs(before - (total - before - atom.nominalLength))
                if imbalance < best?.imbalance ?? .max { best = (index, imbalance) }
            }
            before += atom.nominalLength
        }
        return best?.index
    }

    private static func trimmed(_ atoms: [Atom]) -> [Atom] {
        guard let start = atoms.firstIndex(where: { !$0.isTrimmable }),
              let end = atoms.lastIndex(where: { !$0.isTrimmable }) else { return [] }
        return Array(atoms[start...end])
    }

    func text(date: Date, calendar: Calendar, locale: Locale) -> NotchDateText {
        let render = Self.renderer(date: date, calendar: calendar, locale: locale)
        return NotchDateText(leading: render(leading), trailing: render(trailing))
    }

    func wholeText(date: Date, calendar: Calendar, locale: Locale) -> String {
        Self.renderer(date: date, calendar: calendar, locale: locale)(whole)
    }

    /// Width both wings must offer so no date ever resizes the island.
    func widestHalf(calendar: Calendar, locale: Locale, measure: (String) -> CGFloat) -> CGFloat {
        max(Self.widest(leading, calendar: calendar, locale: locale, measure: measure),
            Self.widest(trailing, calendar: calendar, locale: locale, measure: measure))
    }

    func widestWhole(calendar: Calendar, locale: Locale, measure: (String) -> CGFloat) -> CGFloat {
        Self.widest(whole, calendar: calendar, locale: locale, measure: measure)
    }

    private static func renderer(date: Date, calendar: Calendar, locale: Locale) -> ([Atom]) -> String {
        var calendar = calendar
        calendar.locale = locale
        let parts = calendar.dateComponents([.weekday, .day, .month, .year, .hour, .minute], from: date)
        return { atoms in
            atoms.map { atom -> String in
                switch atom {
                case .token(let token): return token.value(parts, calendar: calendar)
                case .literal(let character, _): return String(character)
                }
            }.joined()
        }
    }

    private static func widest(_ atoms: [Atom], calendar: Calendar, locale: Locale,
                               measure: (String) -> CGFloat) -> CGFloat {
        var calendar = calendar
        calendar.locale = locale
        return measure(atoms.map { atom -> String in
            switch atom {
            case .token(let token):
                return token.candidates(calendar: calendar).max { measure($0) < measure($1) } ?? ""
            case .literal(let character, _): return String(character)
            }
        }.joined())
    }
}

enum NotchDateFormat {
    static let defaultPattern = "DDD | D MMM"
    static let presets = [defaultPattern, "DDDD | D MMMM", "DDD D MMM | HH:mm",
                          "DD/MM/YYYY", "MM/DD/YYYY", "YYYY-MM-DD", "DDDD | DD/MM/YYYY"]
    static let maximumLength = 40

    /// Stored text is user input, and may also arrive through a restored backup.
    static func sanitized(_ raw: String?) -> String {
        // Format characters stay: emoji sequences are joined by one.
        var printable = String.UnicodeScalarView()
        printable.append(contentsOf: (raw ?? "").unicodeScalars.filter {
            $0.properties.generalCategory != .control && !CharacterSet.newlines.contains($0)
        })
        let pattern = String(String(printable).prefix(maximumLength)).trimmingCharacters(in: .whitespaces)
        return NotchDatePattern(pattern).isEmpty ? defaultPattern : pattern
    }

    /// Codes are runs of letters, so `DD` typed after `D` would become a
    /// weekday. A space keeps the added code itself; one that does not fit is
    /// refused rather than cut into a shorter code.
    static func appending(_ token: NotchDateToken, to raw: String) -> String? {
        let fuses = raw.last.map { $0.isLetter || $0.isNumber } ?? false
        let result = raw + (fuses ? " " : "") + token.rawValue
        return result.count <= maximumLength ? result : nil
    }

    /// Names follow the app's language; the calendar stays the user's own.
    static func text(_ raw: String, language: AppLanguage, date: Date = Date()) -> NotchDateText {
        NotchDatePattern(sanitized(raw)).text(date: date, calendar: .autoupdatingCurrent,
                                              locale: Locale(identifier: language.rawValue))
    }

    static func wholeText(_ raw: String, language: AppLanguage, date: Date = Date()) -> String {
        NotchDatePattern(sanitized(raw)).wholeText(date: date, calendar: .autoupdatingCurrent,
                                                   locale: Locale(identifier: language.rawValue))
    }

    static func stored(in defaults: UserDefaults = .standard) -> String {
        sanitized(defaults.object(forKey: DefaultsKey.notchIdleDateFormat) as? String)
    }

    static func pattern(in defaults: UserDefaults = .standard) -> NotchDatePattern {
        NotchDatePattern(stored(in: defaults))
    }
}
