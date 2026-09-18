// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What the service reads out of preferences on every sync.
struct LayoutSwitcherConfig: Equatable {
    var enabled: Bool = false
    var minimumWordLength: Int = Defaults.defaultLayoutSwitcherWordLength

    /// Correct a finished word on its own, without the user asking. Off keeps
    /// the feature on the shortcut alone, which is the only mode that needs no
    /// judgement about what the user meant.
    var automatic: Bool = false
}

/// A physical key on one of the two layers a word is typed on. Without the
/// shifted layer a capital has no pairing, and `Ghbdtn` cannot become `Привет`.
struct LayoutKey: Hashable, Comparable {
    let keyCode: UInt16
    let shifted: Bool

    /// Plain keys sort first, so when a layout puts one glyph on two keys the
    /// unshifted one claims the pairing.
    static func < (lhs: LayoutKey, rhs: LayoutKey) -> Bool {
        lhs.shifted == rhs.shifted ? lhs.keyCode < rhs.keyCode : !lhs.shifted
    }
}

/// Holds back a doubtful correction until a second one agrees with it.
///
/// A confident verdict fires at once. A doubtful one rewrites nothing on its
/// own: only two in a row toward the same layout do, since one odd word is a
/// name or a typo and two are somebody typing on the wrong layout.
struct LayoutConfidenceGate {
    private var pendingTarget: String?

    mutating func admits(_ confidence: LayoutCorrectionConfidence, target: String) -> Bool {
        if confidence == .low, pendingTarget != target {
            pendingTarget = target
            return false
        }
        pendingTarget = nil
        return true
    }

    mutating func reset() {
        pendingTarget = nil
    }
}

/// The word being typed, and the one a space just finished.
///
/// Kept apart from the event tap so that what ends a word, and what a
/// Backspace does to one, is pinned by tests rather than by typing at the app.
struct LayoutTypingBuffer: Equatable {
    enum Ending: Equatable {
        case space
        /// Punctuation no enabled layout reads as a letter. The token includes
        /// it, and the word goes on being typed: the space that follows still
        /// gets the last word.
        case punctuation
        case newline
    }

    struct Finished: Equatable {
        let token: String
        let ending: Ending
    }

    /// Bounded so a session of typing cannot grow it without limit.
    static let limit = 128

    /// Only ever the token under the caret: any whitespace empties it.
    private(set) var typing = ""
    /// The token the last space finished. Noticing the wrong layout usually
    /// happens a beat after the space, so the shortcut can still reach it.
    /// Only a space: Return committed the line somewhere, and a word that
    /// ended any other way is not one keystroke behind the caret.
    private(set) var lastFinished = ""

    mutating func type(_ typed: String, earlyBoundaries: Set<Character>) -> Finished? {
        guard !typed.isEmpty else { return nil }
        guard typed.allSatisfy(\.isWhitespace) else {
            let hadWord = typing.contains { $0.isLetter || $0.isNumber }
            typing.append(typed)
            if typing.count > Self.limit { typing.removeFirst(typing.count - Self.limit) }
            guard hadWord, typed.count == 1, let character = typed.first,
                  earlyBoundaries.contains(character)
            else { return nil }
            return Finished(token: typing, ending: .punctuation)
        }
        let token = typing
        typing = ""
        lastFinished = typed == " " ? token : ""
        guard !token.isEmpty else { return nil }
        if typed == " " { return Finished(token: token, ending: .space) }
        return typed.allSatisfy(\.isNewline) ? Finished(token: token, ending: .newline) : nil
    }

    mutating func deleteBackward() {
        if !typing.isEmpty {
            typing.removeLast()
        } else if !lastFinished.isEmpty {
            // The space just went, so the caret is back against the word and
            // the word is being typed again. Leaving it as finished would have
            // the next correction delete a space that is no longer there.
            typing = lastFinished
            lastFinished = ""
        }
    }

    mutating func replaceTyping(_ token: String, with replacement: String) {
        guard typing.hasSuffix(token) else { return }
        typing.removeLast(token.count)
        typing.append(replacement)
    }

    mutating func replaceLastFinished(_ token: String, with replacement: String) {
        if lastFinished == token { lastFinished = replacement }
    }

    mutating func clear() {
        typing = ""
        lastFinished = ""
    }
}

/// A glyph-for-glyph map between two keyboard layouts.
///
/// Derived from what each physical key produces on each layout, so a pair the
/// project never heard of works the same as the ones it did. `forward` reads
/// from the layout the text was typed on; `reverse` is its exact inverse,
/// which is what makes applying the shortcut twice a lossless round trip.
struct LayoutGlyphTable: Equatable {
    let forward: [Character: Character]
    let reverse: [Character: Character]
    /// Glyphs both layouts put on the same key. They carry no information about
    /// which layout was meant, so they are neither a correction nor a reason to
    /// refuse one: retyping passes them through untouched. Without this, a pair
    /// like US and German, which differ on a handful of keys, would fail on the
    /// first shared letter and the feature would never fire at all.
    let shared: Set<Character>

    /// Two input sources for the same layout have nothing to correct between.
    var isUsable: Bool { !forward.isEmpty }

    /// Digits and the hyphen sit on the same glyph in most layout pairs, so a
    /// token like `web3` survives instead of being discarded whole. A pair
    /// that does move them maps them through `forward` like any other key,
    /// because the table is consulted first.
    static let passthrough: Set<Character> = Set("0123456789-")

    func map(_ word: String, using table: [Character: Character]) -> String? {
        var result = ""
        result.reserveCapacity(word.count)
        var changedAny = false
        for character in word {
            if let mapped = table[character] {
                result.append(mapped)
                changedAny = true
            } else if shared.contains(character) || Self.passthrough.contains(character) {
                result.append(character)
            } else {
                return nil
            }
        }
        // A word that comes out exactly as it went in is not a correction.
        return changedAny ? result : nil
    }

    func mapForward(_ word: String) -> String? { map(word, using: forward) }
    func mapReverse(_ word: String) -> String? { map(word, using: reverse) }
}

enum LayoutSwitcherSupport {
    /// Pairs two keycode-to-glyph readings into a bidirectional glyph map.
    ///
    /// Kept free of Text Input Sources so the pairing itself stays testable;
    /// the service does the reading and hands the two dictionaries in.
    static func table<Key: Hashable & Comparable>(from source: [Key: String],
                                                  to target: [Key: String]) -> LayoutGlyphTable {
        var forward: [Character: Character] = [:]
        var reverse: [Character: Character] = [:]
        var shared: Set<Character> = []
        // Sorted, because "the first pairing wins" below has to mean the same
        // key on every launch and a dictionary walks in a different order each.
        for key in source.keys.sorted() {
            guard let sourceGlyph = source[key],
                  let targetGlyph = target[key],
                  let from = singleCharacter(sourceGlyph),
                  let to = singleCharacter(targetGlyph)
            else { continue }
            guard from != to else {
                shared.insert(from)
                continue
            }
            // A key already claimed by an earlier keycode wins. Layouts do put
            // the same glyph on two keys, and the first pairing is the one the
            // reverse direction can undo.
            if forward[from] == nil { forward[from] = to }
            if reverse[to] == nil { reverse[to] = from }
        }
        // Only a bijection round trips. Drop any pairing whose reverse landed
        // on a different key, rather than silently corrupting that character.
        forward = forward.filter { reverse[$0.value] == $0.key }
        reverse = reverse.filter { forward[$0.value] == $0.key }
        // A glyph that moved on some key cannot also stand for itself, or the
        // round trip would depend on which rule ran first.
        shared.subtract(forward.keys)
        shared.subtract(reverse.keys)
        return LayoutGlyphTable(forward: forward, reverse: reverse, shared: shared)
    }

    /// Punctuation that may end a word the moment it is typed.
    ///
    /// `!` is `!` everywhere, so `ghbdtn!` can be looked at right away. A
    /// comma cannot: its key is `б` on a Russian layout, and `cgfcb,j` is one
    /// word. The tap only sees the character, not the layout it came from, so
    /// a character qualifies only if every key that types it, on any enabled
    /// layout, types punctuation on all the others too. Anything else waits
    /// for the space, where the whole token is weighed.
    static func earlyBoundaries<Key: Hashable>(in layouts: [[Key: String]]) -> Set<Character> {
        guard layouts.count > 1 else { return [] }
        func isWordy(_ glyph: String?) -> Bool {
            glyph?.contains { $0.isLetter || $0.isNumber } ?? false
        }
        var safe: Set<Character> = []
        var unsafe: Set<Character> = []
        for layout in layouts {
            for (key, glyph) in layout {
                guard let character = singleCharacter(glyph), !isWordy(glyph) else { continue }
                if layouts.contains(where: { isWordy($0[key]) }) {
                    unsafe.insert(character)
                } else {
                    safe.insert(character)
                }
            }
        }
        return safe.subtracting(unsafe)
    }

    /// Glyphs worth pairing: exactly one character, and something a person can
    /// type into a word. Return, Tab and Space share the keycode range with
    /// the letters and would otherwise pair as if they were text.
    static func singleCharacter(_ glyph: String) -> Character? {
        guard glyph.count == 1, let character = glyph.first else { return nil }
        guard let scalar = character.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar),
              !CharacterSet.whitespacesAndNewlines.contains(scalar)
        else { return nil }
        return character
    }

    /// The word ending at the caret. Splitting on whitespace alone keeps
    /// punctuation attached, which is what the user sees as one token.
    static func trailingWord(in text: String) -> String {
        String(text.reversed().prefix { !$0.isWhitespace }.reversed())
    }

    /// Whether a token is worth offering to correct at all. The shortcut path
    /// skips this: the user pressing it has already answered the question.
    static func isCorrectable(_ word: String, minimumLength: Int) -> Bool {
        guard word.count >= minimumLength else { return false }
        guard !word.allSatisfy({ $0.isNumber || $0 == "-" }) else { return false }
        return !looksStructured(word)
    }

    /// Tokens that mean something to a machine rather than to a reader. A URL,
    /// an address, a path, an identifier in camel case: retyping any of them in
    /// another layout is never what was wanted.
    ///
    /// A dot inside the token is deliberately not on this list. It is the `ю`
    /// key, and refusing it here kept every `-ют`, `-ую` and `-юсь` word from
    /// ever being looked at. `file.txt` is turned away later, by the scorer,
    /// for the better reason that its other spelling is not a word.
    static func looksStructured(_ word: String) -> Bool {
        if word.contains("://") || word.contains("@") || word.contains("/") { return true }
        if word.contains("_") || hasBracketPair(word) { return true }
        let hasInnerCapital = word.dropFirst().contains { $0.isUppercase }
        let hasLower = word.contains { $0.isLowercase }
        return hasInnerCapital && hasLower
    }

    /// An opening bracket with its partner later in the token is code:
    /// `[]Transition`, `map[string]int`, `<div>`, `{name}`. Read as Russian on
    /// the wrong layout a pair would be `х…ъ` inside one word, which the
    /// language barely has. The reverse order is left alone on purpose: `]…[`
    /// is `ъ…х`, the `объехать` family.
    private static func hasBracketPair(_ word: String) -> Bool {
        func encloses(_ open: Character, _ close: Character) -> Bool {
            guard let start = word.firstIndex(of: open) else { return false }
            return word[word.index(after: start)...].contains(close)
        }
        if encloses("[", "]") || encloses("<", ">") { return true }
        if word.contains("{") && word.contains("}") { return true }
        return word.filter { $0 == "`" }.count >= 2
    }
}
