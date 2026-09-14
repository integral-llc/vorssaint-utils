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
    static func table(from source: [UInt16: String], to target: [UInt16: String]) -> LayoutGlyphTable {
        var forward: [Character: Character] = [:]
        var reverse: [Character: Character] = [:]
        var shared: Set<Character> = []
        for (keyCode, sourceGlyph) in source {
            guard let targetGlyph = target[keyCode],
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
    static func looksStructured(_ word: String) -> Bool {
        if word.contains("://") || word.contains("@") || word.contains("/") { return true }
        if word.contains(".") && !word.hasSuffix(".") { return true }
        if word.contains("_") { return true }
        let hasInnerCapital = word.dropFirst().contains { $0.isUppercase }
        let hasLower = word.contains { $0.isLowercase }
        return hasInnerCapital && hasLower
    }
}
