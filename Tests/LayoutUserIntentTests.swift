// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// When the user is already handling a word: taking a correction back by
/// hand, switching the layout mid-word, typing in an excluded app, or
/// changing their mind about a refused word. Event sequences in, decisions
/// out, without an event tap.
enum LayoutUserIntentTests {
    private typealias Correction = LayoutCorrectionWatch.Correction

    static func run(_ suite: TestSuite) {
        revertChecks(suite)
        skipChecks(suite)
        exclusionChecks(suite)
        refusedListChecks(suite)
    }

    private static let correction = Correction(original: "ghbdtn", corrected: "привет",
                                               word: "ghbdtn", previousSourceID: "us")

    /// Plays keystrokes into a buffer and watch the way the service does.
    /// `<` is Backspace. Returns what each finished token amounted to.
    private static func play(_ keys: String, buffer: inout LayoutTypingBuffer,
                             watch: inout LayoutCorrectionWatch) -> [String] {
        var outcomes: [String] = []
        for key in keys {
            if key == "<" {
                buffer.deleteBackward()
                watch.deleted(typing: buffer.typing, lastFinished: buffer.lastFinished)
                continue
            }
            let text = String(key)
            watch.typed(text)
            guard let finished = buffer.type(text, earlyBoundaries: []) else { continue }
            if let undone = watch.finished(finished.token) {
                outcomes.append("reverted \(undone.word)")
            } else {
                outcomes.append("judge \(finished.token)")
            }
        }
        return outcomes
    }

    /// The state right after automatic mode rewrote `ghbdtn ` as `привет `.
    private static func afterCorrection() -> (LayoutTypingBuffer, LayoutCorrectionWatch) {
        var buffer = LayoutTypingBuffer()
        _ = buffer.type("ghbdtn", earlyBoundaries: [])
        _ = buffer.type(" ", earlyBoundaries: [])
        buffer.replaceLastFinished("ghbdtn", with: "привет")
        var watch = LayoutCorrectionWatch()
        watch.record(correction)
        return (buffer, watch)
    }

    private static func revertChecks(_ suite: TestSuite) {
        var (buffer, watch) = afterCorrection()
        suite.expect(play("<<<<<<<ghbdtn ", buffer: &buffer, watch: &watch) == ["reverted ghbdtn"],
                     "deleting a correction and retyping the original takes it back")
        suite.expect(watch.last == nil, "a taken-back correction is no longer there to undo")

        (buffer, watch) = afterCorrection()
        suite.expect(play("<<<<<<<ghbdtv ", buffer: &buffer, watch: &watch) == ["judge ghbdtv"],
                     "a different word typed over a correction is judged like any other")

        (buffer, watch) = afterCorrection()
        suite.expect(play("lf ", buffer: &buffer, watch: &watch) == ["judge lf"] && watch.last == nil,
                     "typing on past a correction lets it stand")

        (buffer, watch) = afterCorrection()
        suite.expect(play("< ", buffer: &buffer, watch: &watch) == ["judge привет"] && watch.last == correction,
                     "taking back only the space is not taking back the word")

        (buffer, watch) = afterCorrection()
        _ = play("<<<", buffer: &buffer, watch: &watch)
        buffer.clear()
        watch.clear()
        suite.expect(play("ghbdtn ", buffer: &buffer, watch: &watch) == ["judge ghbdtn"],
                     "after the caret moves, retyping the original is a new word")
    }

    private static func skipChecks(_ suite: TestSuite) {
        var buffer = LayoutTypingBuffer()
        _ = buffer.type("ghb", earlyBoundaries: [])
        buffer.skipCurrentWord()
        _ = buffer.type("dtn", earlyBoundaries: [])
        let skipped = buffer.type(" ", earlyBoundaries: [])
        suite.expect(skipped?.isSkipped == true, "a word the layout was switched in by hand is skipped")
        _ = buffer.type("ntcn", earlyBoundaries: [])
        suite.expect(buffer.type(" ", earlyBoundaries: [])?.isSkipped == false,
                     "the word after it is judged again")

        buffer = LayoutTypingBuffer()
        buffer.skipCurrentWord()
        _ = buffer.type("ntcn", earlyBoundaries: [])
        suite.expect(buffer.type(" ", earlyBoundaries: [])?.isSkipped == false,
                     "a switch between words skips nothing")

        buffer = LayoutTypingBuffer()
        _ = buffer.type("ghb", earlyBoundaries: [])
        buffer.skipCurrentWord()
        (0..<3).forEach { _ in buffer.deleteBackward() }
        _ = buffer.type("ghbdtn", earlyBoundaries: [])
        suite.expect(buffer.type(" ", earlyBoundaries: [])?.isSkipped == false,
                     "deleting the word and starting over starts a new word")

        buffer = LayoutTypingBuffer()
        _ = buffer.type("ghbdtn", earlyBoundaries: ["!"])
        buffer.skipCurrentWord()
        suite.expect(buffer.type("!", earlyBoundaries: ["!"])?.isSkipped == true
                        && buffer.type(" ", earlyBoundaries: ["!"])?.isSkipped == true,
                     "the skip lasts through early punctuation to the space")
        ownSwitchChecks(suite)
    }

    private static func ownSwitchChecks(_ suite: TestSuite) {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var own = LayoutOwnSwitches()
        own.expect("ru", at: start)
        suite.expect(own.claim("ru", at: start.addingTimeInterval(0.2)),
                     "the switch a correction makes is not the user's")
        suite.expect(!own.claim("ru", at: start.addingTimeInterval(0.3)),
                     "one switch of ours accounts for one notification")
        suite.expect(!own.claim("us", at: start), "a switch to another layout is the user's")

        own.expect("us", at: start)
        suite.expect(!own.claim("us", at: start.addingTimeInterval(LayoutOwnSwitches.window + 0.1)),
                     "a switch long after ours is the user's")

        own.expect("ru", at: start)
        own.expect("us", at: start)
        suite.expect(own.claim("ru", at: start) && own.claim("us", at: start),
                     "a correction and its undo in quick succession are both ours")
    }

    private static func exclusionChecks(_ suite: TestSuite) {
        let excluded: Set<String> = ["com.apple.Terminal"]
        suite.expect(!LayoutSwitcherSupport.correctsAutomatically(in: "com.apple.Terminal", excluding: excluded),
                     "an excluded app gets no automatic correction")
        suite.expect(LayoutSwitcherSupport.correctsAutomatically(in: "com.apple.Notes", excluding: excluded),
                     "any other app does")
        suite.expect(LayoutSwitcherSupport.correctsAutomatically(in: nil, excluding: excluded),
                     "an app with no bundle identifier cannot be on the list")
        suite.expect(Set(Defaults.sanitizedBundleIdentifierList([" com.apple.Terminal", "", "com.apple.Terminal"]))
                        == excluded,
                     "the saved list is sanitised like every other app list")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.layoutSwitcherExcludedApps),
                     "the excluded apps travel in a settings backup; they are not typed text")
    }

    private static func refusedListChecks(_ suite: TestSuite) {
        let vocabulary = LayoutVocabulary(capacity: 100, persistEvery: 100, defaults: nil)
        vocabulary.refuse("ghbdtn")
        vocabulary.refuse("Ntcn")
        suite.expect(vocabulary.refusedWords == ["ntcn", "ghbdtn"], "refused words are listed, newest first")
        vocabulary.removeRefusal("GHBDTN")
        suite.expect(vocabulary.refusedWords == ["ntcn"] && !vocabulary.isRefused("ghbdtn"),
                     "one refused word can be taken off the list")
        vocabulary.removeRefusal("absent")
        suite.expect(vocabulary.refusedWords == ["ntcn"], "removing a word that is not there changes nothing")
        vocabulary.clear()
        suite.expect(vocabulary.refusedWords.isEmpty, "forgetting learned words clears the list too")

        let suiteName = "com.vorssaint.tests.layout-refused-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let stored = LayoutVocabulary(capacity: 100, persistEvery: 100, defaults: defaults)
        stored.refuse("ghbdtn")
        stored.refuse("ntcn")
        stored.removeRefusal("ghbdtn")
        let reloaded = LayoutVocabulary(capacity: 100, persistEvery: 100, defaults: defaults)
        suite.expect(reloaded.refusedWords == ["ntcn"], "a removal is saved at once")
    }
}
