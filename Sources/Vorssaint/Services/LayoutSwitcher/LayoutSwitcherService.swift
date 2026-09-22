// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import CoreGraphics
import Foundation

/// Retypes a word that went in on the wrong keyboard layout.
///
/// The pairing comes from what each physical key produces on each of the
/// layouts the user actually enabled, so any pair works, not a list of the
/// ones somebody wrote a table for. Applying it twice returns the original.
final class LayoutSwitcherService: ObservableObject {
    static let shared = LayoutSwitcherService()

    @Published private(set) var isRunning = false

    private let eventLock = NSLock()
    private let lifecycleLock = NSLock()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var shouldStopTapThread = false
    private var pendingStartAfterStop = false
    private var lifecycleGeneration: UInt = 0
    private var typingBuffer = LayoutTypingBuffer()
    /// Punctuation that ends a word the moment it is typed. Read off the
    /// enabled layouts together with `layoutCache`, and as stale as it is.
    private var earlyBoundaries: Set<Character> = []
    private var config = LayoutSwitcherConfig()
    private var tableCache: [String: [LayoutKey: String]] = [:]
    /// Asking the system for the enabled layouts on every finished word is a
    /// database query per space bar. The list only changes when the user edits
    /// it, and the system says so when they do.
    private var layoutCache: [EnabledLayout]?
    private var gate = LayoutConfidenceGate()
    private var context = LayoutSentenceContext()
    /// What automatic mode last rewrote, so the shortcut can take it back.
    private var lastAutomatic: AutomaticCorrection?
    /// Counts everything that can move the caret or change the text behind it.
    /// A correction is decided a moment after its word finished, and it only
    /// goes ahead if this still reads what it read then.
    private var activity: UInt64 = 0
    private let vocabulary = LayoutVocabulary.shared
    private let evidence: BundledLanguageEvidence
    private let scorer: LayoutDecisionScorer
    private let hotkey = QuickToolHotkey(id: 59)

    /// Keycodes 0 through 50 are the block a word is typed on. Everything
    /// above is a modifier, a function key or the keypad, which no layout
    /// pairing has an opinion about.
    private static let typingKeyCodes: [UInt16] = Array(0...50)

    private struct EnabledLayout {
        let source: TISInputSource
        let id: String
        /// The language the system records for the layout. One without any
        /// cannot be judged, and automatic mode leaves its words alone.
        let language: String?
    }

    private struct AutomaticCorrection {
        let original: String
        let corrected: String
        /// The word inside `original`, without the punctuation around it.
        let word: String
        /// nil when the layout did not follow the word, so there is none to restore.
        let previousSourceID: String?
    }

    private struct FinishedWord {
        let token: String
        let ending: LayoutTypingBuffer.Ending
        /// The modifiers Return was pressed with. Shift-Return is a new line in
        /// apps where Return alone sends, and putting back the wrong one sends.
        let flags: CGEventFlags
        let activity: UInt64
    }

    private enum Outcome {
        case rewrite(Candidate)
        case keep(word: String)
        case undecided
    }

    private struct ShortcutTarget {
        let word: String
        let deleteCount: Int
        let suffix: String
        /// Set when the word is one automatic mode just rewrote.
        let automatic: AutomaticCorrection?
    }

    private struct Candidate {
        let layout: EnabledLayout
        let language: String
        let word: String
        let replacement: String
        let verdict: LayoutDecisionScorer.Verdict
    }

    private init() {
        evidence = BundledLanguageEvidence()
        var scorer = LayoutDecisionScorer(evidence: evidence)
        scorer.vocabulary = vocabulary
        self.scorer = scorer
        hotkey.onPress = { [weak self] in self?.correctWordAtCaret() }
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourcesChanged),
            name: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil
        )
        // Another app is another piece of writing. Neither the sentence so far
        // nor a doubtful correction waiting for a second carries over.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func inputSourcesChanged() {
        eventLock.withLock {
            tableCache.removeAll()
            layoutCache = nil
            earlyBoundaries = []
        }
        // The tap cannot ask the system for layouts, so they are read again
        // here rather than whenever the next word happens to need them.
        _ = enabledLayouts()
    }

    @objc private func applicationChanged() {
        eventLock.withLock {
            context.reset()
            gate.reset()
        }
    }

    /// Settings calls this. Everything learned goes, in memory and on disk.
    func forgetLearnedWords() {
        vocabulary.clear()
    }

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let nextConfig = LayoutSwitcherConfig(
            enabled: AppFeature.layoutSwitcher.isAvailable
                && defaults.bool(forKey: DefaultsKey.layoutSwitcherEnabled),
            minimumWordLength: Defaults.sanitizedLayoutSwitcherWordLength(
                defaults.integer(forKey: DefaultsKey.layoutSwitcherMinimumWordLength)
            ),
            automatic: defaults.bool(forKey: DefaultsKey.layoutSwitcherAutomatic)
        )
        eventLock.withLock {
            config = nextConfig
            clearTypingState()
        }
        // Also reads the enabled layouts, which the tap needs before the
        // first word and cannot ask for itself.
        if nextConfig.enabled, nextConfig.automatic { warmUpEvidence() }
        hotkey.sync(enabled: nextConfig.enabled,
                    shortcut: GlobalShortcutRole.layoutSwitcher.savedShortcut,
                    storageKey: GlobalShortcutRole.layoutSwitcher.storageKey)

        if SessionActivitySupport.tapShouldRun(featureWanted: nextConfig.enabled,
                                               accessibilityGranted: AXIsProcessTrusted(),
                                               sessionIsActive: SessionActivity.shared.isActive) {
            start()
        } else {
            stop()
        }
    }

    func suspend() {
        stop()
    }

    // MARK: - Correcting

    /// The shortcut path. Retypes the word the caret sits behind, or the
    /// selection when there is one, without asking whether it looked wrong:
    /// pressing the shortcut is the answer to that question.
    @discardableResult
    func correctWordAtCaret() -> Bool {
        guard Thread.isMainThread else {
            return DispatchQueue.main.sync { self.correctWordAtCaret() }
        }
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled() else { return false }

        let selection = CommandBarSelectionReader.readSelectedText()
        let target = eventLock.withLock { () -> ShortcutTarget? in
            if !selection.isEmpty {
                // A selection is already highlighted; one Delete clears it.
                return ShortcutTarget(word: selection, deleteCount: 1, suffix: "", automatic: nil)
            }
            let typing = LayoutSwitcherSupport.trailingWord(in: typingBuffer.typing)
            if !typing.isEmpty {
                // Backspacing over the space puts a corrected word back under
                // the caret, and it can still be taken back from there.
                return ShortcutTarget(word: typing, deleteCount: typing.count, suffix: "",
                                      automatic: lastAutomatic?.corrected == typing ? lastAutomatic : nil)
            }
            let finished = typingBuffer.lastFinished
            guard !finished.isEmpty else { return nil }
            // The boundary is past the word, so it goes and comes back with it.
            return ShortcutTarget(word: finished,
                                  deleteCount: finished.count + 1,
                                  suffix: " ",
                                  automatic: lastAutomatic?.corrected == finished ? lastAutomatic : nil)
        }
        // An automatic correction is taken back to exactly what was typed.
        // Mapping it again could land on a third layout's spelling instead.
        guard let target, let corrected = target.automatic?.original ?? retyped(target.word)
        else { return false }

        let replaced = TextSnippetService.postExpansion(
            deleteCount: target.deleteCount,
            text: corrected + target.suffix,
            trailingKeyCode: nil,
            trailingFlags: []
        )
        guard replaced else { return false }
        eventLock.withLock {
            // Pressing the shortcut again has to undo, not re-apply.
            if target.suffix.isEmpty {
                typingBuffer.replaceTyping(target.word, with: corrected)
            } else {
                typingBuffer.replaceLastFinished(target.word, with: corrected)
            }
            activity &+= 1
            guard target.automatic != nil else { return }
            lastAutomatic = nil
            // The correction told the sentence it was in the other language.
            // It was wrong about the word, so it is not trusted about that.
            context.reset()
        }
        if let undone = target.automatic {
            vocabulary.refuse(undone.word)
            // Taking back an automatic correction also takes back the layout
            // it switched to, or the next word goes in on the wrong one again.
            if let previous = undone.previousSourceID { selectLayout(id: previous) }
        }
        return true
    }

    /// The other layout's spelling of `word`, or nil when no enabled layout
    /// maps every character of it.
    func retyped(_ word: String) -> String? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let currentID = KeyboardLayoutGlyph.property(current, kTISPropertyInputSourceID),
              let currentGlyphs = glyphs(for: current, id: currentID)
        else { return nil }

        for layout in enabledLayouts() where layout.id != currentID {
            guard let candidateGlyphs = glyphs(for: layout.source, id: layout.id) else { continue }
            // Reverse: the text carries the candidate layout's glyphs and the
            // user meant the one now selected. That is the common case, since
            // noticing the mistake is what makes them switch layouts first.
            let table = LayoutSwitcherSupport.table(from: candidateGlyphs, to: currentGlyphs)
            guard table.isUsable else { continue }
            if let corrected = table.mapForward(word) { return corrected }
            if let corrected = table.mapReverse(word) { return corrected }
        }
        return nil
    }

    private func glyphs(for source: TISInputSource, id: String) -> [LayoutKey: String]? {
        if let cached = eventLock.withLock({ tableCache[id] }) { return cached }
        guard let data = KeyboardLayoutGlyph.layoutData(for: source) else { return nil }
        var glyphs: [LayoutKey: String] = [:]
        for shifted in [false, true] {
            for keyCode in Self.typingKeyCodes {
                guard let glyph = KeyboardLayoutGlyph.character(in: data,
                                                                keyCode: keyCode,
                                                                carbonModifiers: shifted ? shiftKey : 0),
                      LayoutSwitcherSupport.singleCharacter(glyph) != nil
                else { continue }
                glyphs[LayoutKey(keyCode: keyCode, shifted: shifted)] = glyph
            }
        }
        guard !glyphs.isEmpty else { return nil }
        eventLock.withLock { tableCache[id] = glyphs }
        return glyphs
    }

    private func enabledLayouts() -> [EnabledLayout] {
        if let cached = eventLock.withLock({ layoutCache }) { return cached }
        let filter = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String]
        let sources = TISCreateInputSourceList(filter as CFDictionary, false)?
            .takeRetainedValue() as? [TISInputSource] ?? []
        let layouts = sources.compactMap { source -> EnabledLayout? in
            guard let id = KeyboardLayoutGlyph.property(source, kTISPropertyInputSourceID) else { return nil }
            return EnabledLayout(source: source, id: id, language: Self.language(of: source))
        }
        let boundaries = LayoutSwitcherSupport.earlyBoundaries(
            in: layouts.compactMap { glyphs(for: $0.source, id: $0.id) })
        eventLock.withLock {
            layoutCache = layouts
            earlyBoundaries = boundaries
        }
        return layouts
    }

    private static func language(of source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages),
              let languages = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String]
        else { return nil }
        return languages.first
    }

    @discardableResult
    private func selectLayout(id: String) -> Bool {
        guard let layout = enabledLayouts().first(where: { $0.id == id }) else { return false }
        return TISSelectInputSource(layout.source) == noErr
    }

    /// Off the main thread and ahead of need: the first read parses megabytes.
    private func warmUpEvidence() {
        let languages = Set(enabledLayouts().compactMap(\.language))
        DispatchQueue.global(qos: .userInitiated).async { [evidence] in
            evidence.warmUp(Array(languages))
        }
    }

    // MARK: - Lifecycle

    private func start() {
        eventLock.withLock { clearTypingState() }

        let startState = lifecycleLock.withLock { () -> (thread: Thread?, publishRunning: Bool, generation: UInt) in
            if tapThread != nil {
                if shouldStopTapThread {
                    pendingStartAfterStop = true
                    return (nil, false, lifecycleGeneration)
                }
                return (nil, true, lifecycleGeneration)
            }
            shouldStopTapThread = false
            pendingStartAfterStop = false
            lifecycleGeneration &+= 1
            let generation = lifecycleGeneration
            let thread = Thread { [weak self] in
                self?.runEventTap(generation: generation)
            }
            thread.name = "Vorssaint Layout Switcher"
            thread.qualityOfService = .userInteractive
            tapThread = thread
            return (thread, false, generation)
        }

        if let thread = startState.thread {
            thread.start()
        } else if startState.publishRunning {
            publishRunning(true, generation: startState.generation)
        }
    }

    private func stop() {
        eventLock.withLock { clearTypingState() }
        vocabulary.flush()

        let snapshot = lifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, threadExists: Bool, generation: UInt) in
            shouldStopTapThread = true
            pendingStartAfterStop = false
            lifecycleGeneration &+= 1
            return (tapRunLoop, tap, tapThread != nil, lifecycleGeneration)
        }

        if let tap = snapshot.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop = snapshot.runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        } else if !snapshot.threadExists {
            lifecycleLock.withLock {
                shouldStopTapThread = false
                tapThread = nil
            }
        }
        publishRunning(false, generation: snapshot.generation)
    }

    private func runEventTap(generation: UInt) {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            lifecycleLock.withLock { tapRunLoop = runLoop }

            let shouldStopBeforeCreatingTap = lifecycleLock.withLock { shouldStopTapThread }
            guard !shouldStopBeforeCreatingTap else {
                if clearEventTapThread() {
                    start()
                } else {
                    publishRunning(false, generation: generation)
                }
                return
            }

            let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
                | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
                | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<LayoutSwitcherService>.fromOpaque(userInfo).takeUnretainedValue()
                    return service.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                _ = clearEventTapThread()
                publishRunning(false, generation: generation)
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            lifecycleLock.withLock {
                self.tap = tap
                runLoopSource = source
            }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            eventLock.withLock { clearTypingState() }

            let shouldStop = lifecycleLock.withLock { shouldStopTapThread }
            if shouldStop {
                CGEvent.tapEnable(tap: tap, enable: false)
            } else {
                publishRunning(true, generation: generation)
                CFRunLoopRun()
            }

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            eventLock.withLock { clearTypingState() }
            if clearEventTapThread() {
                start()
            } else {
                publishRunning(false, generation: generation)
            }
        }
    }

    private func clearEventTapThread() -> Bool {
        lifecycleLock.withLock {
            let shouldRestart = pendingStartAfterStop
            tap = nil
            runLoopSource = nil
            tapRunLoop = nil
            tapThread = nil
            shouldStopTapThread = false
            pendingStartAfterStop = false
            return shouldRestart
        }
    }

    private func publishRunning(_ running: Bool, generation: UInt) {
        let update = { [weak self] in
            guard let self else { return }
            let isCurrent = self.lifecycleLock.withLock { generation == self.lifecycleGeneration }
            guard isCurrent else { return }
            self.isRunning = running
        }

        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let currentTap = lifecycleLock.withLock { shouldStopTapThread ? nil : tap }
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let currentTap {
                CGEvent.tapEnable(tap: currentTap, enable: true)
            } else {
                DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
            }
            return Unmanaged.passUnretained(event)
        }

        // A click moves the caret somewhere the buffer knows nothing about.
        if type == .leftMouseDown || type == .rightMouseDown {
            if !AssistiveKeyboard.ownsPoint(event.location) { resetBuffer() }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        guard event.getIntegerValueField(.eventSourceUserData) != TextSnippetService.syntheticMarker else {
            return Unmanaged.passUnretained(event)
        }
        // Secure input means a password field. Nothing typed there is kept,
        // read, or offered for correction.
        guard !IsSecureEventInputEnabled() else {
            resetBuffer()
            return Unmanaged.passUnretained(event)
        }
        if !event.flags.intersection([.maskCommand, .maskControl]).isEmpty {
            resetBuffer()
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        switch keyCode {
        case kVK_Delete:
            eventLock.withLock {
                activity &+= 1
                typingBuffer.deleteBackward()
            }
            return Unmanaged.passUnretained(event)
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Escape,
             kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete, kVK_Tab,
             kVK_ANSI_KeypadEnter:
            resetBuffer()
            return Unmanaged.passUnretained(event)
        default:
            break
        }

        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4,
                                       actualStringLength: &length,
                                       unicodeString: &characters)
        guard length > 0 else { return Unmanaged.passUnretained(event) }
        let typed = String(utf16CodeUnits: characters, count: length)

        if let finished = eventLock.withLock({ record(typed, flags: event.flags) }) {
            // Return is judged a moment later: the app has to have acted on it
            // before the text can show whether it was a new line or a send.
            let delay: DispatchTimeInterval = finished.ending == .newline ? .milliseconds(40) : .never
            let work = { [weak self] in self?.correctFinishedWord(finished); return }
            if delay == .never {
                DispatchQueue.main.async(execute: work)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    /// Takes one keystroke's text into the buffer. Returns the token it
    /// finished when automatic mode should look at it. Caller holds `eventLock`.
    private func record(_ typed: String, flags: CGEventFlags) -> FinishedWord? {
        activity &+= 1
        guard config.enabled else { return nil }
        // The corrected word is no longer the last thing that happened.
        if !typed.allSatisfy(\.isWhitespace) { lastAutomatic = nil }
        guard let finished = typingBuffer.type(typed, earlyBoundaries: config.automatic ? earlyBoundaries : []),
              config.automatic,
              // Already rewritten when its punctuation went in; the space
              // after it has nothing left to decide.
              finished.token != lastAutomatic?.corrected,
              LayoutSwitcherSupport.isCorrectable(finished.token, minimumLength: config.minimumWordLength)
        else { return nil }
        return FinishedWord(token: finished.token, ending: finished.ending, flags: flags, activity: activity)
    }

    /// Automatic mode. The word is already in the text and the caret has moved
    /// past whatever ended it, so that goes and comes back with the word.
    ///
    /// Being able to spell a word on another layout is not a reason to: every
    /// English word has a Cyrillic spelling. The word is rewritten only when
    /// the other spelling is clearly the better word, and the layout follows
    /// it so the rest of the sentence goes in right.
    private func correctFinishedWord(_ finished: FinishedWord) {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let currentID = KeyboardLayoutGlyph.property(source, kTISPropertyInputSourceID),
              let current = enabledLayouts().first(where: { $0.id == currentID }),
              let typedLanguage = current.language
        else { return }
        let now = Date()

        switch outcome(for: finished.token, typedOn: current, language: typedLanguage, at: now) {
        case .undecided:
            return
        case .keep(let word):
            // The space after early punctuation sees the same word again, and
            // that is where it is counted.
            guard finished.ending != .punctuation else { return }
            eventLock.withLock {
                // A word that stood breaks a run of doubtful corrections: two
                // of them forty words apart are not somebody on the wrong layout.
                gate.reset()
                context.record(typedLanguage, at: now)
            }
            vocabulary.recordTyped(word)
        case .rewrite(let candidate):
            rewrite(finished, as: candidate, from: currentID, at: now)
        }
    }

    private func rewrite(_ finished: FinishedWord, as candidate: Candidate,
                         from currentID: String, at now: Date) {
        let confident = candidate.verdict.confidence == .high
        let goesAhead = eventLock.withLock { () -> Bool in
            // Anything typed or clicked since means the text behind the caret
            // is no longer the text that was judged.
            guard activity == finished.activity else { return false }
            // A doubtful verdict waits for a second one, and only a space asks
            // the gate: the space after early punctuation brings the same word
            // round again, and asking twice would count one word as two.
            return finished.ending == .space
                ? gate.admits(candidate.verdict.confidence, target: candidate.layout.id)
                : confident
        }
        guard goesAhead, replaceText(of: finished, with: candidate.replacement) else { return }
        let followed = TISSelectInputSource(candidate.layout.source) == noErr
        eventLock.withLock {
            context.record(candidate.language, at: now)
            switch finished.ending {
            case .space: typingBuffer.replaceLastFinished(finished.token, with: candidate.replacement)
            case .punctuation: typingBuffer.replaceTyping(finished.token, with: candidate.replacement)
            case .newline: return
            }
            lastAutomatic = AutomaticCorrection(original: finished.token,
                                                corrected: candidate.replacement,
                                                word: candidate.word,
                                                previousSourceID: followed ? currentID : nil)
        }
    }

    /// False only when nothing should follow. After Return the text may be
    /// out of reach, and the layout following the word is still worth having.
    private func replaceText(of finished: FinishedWord, with replacement: String) -> Bool {
        switch finished.ending {
        case .space:
            return TextSnippetService.postExpansion(deleteCount: finished.token.count + 1,
                                                    text: replacement + " ",
                                                    trailingKeyCode: nil,
                                                    trailingFlags: [])
        case .punctuation:
            return TextSnippetService.postExpansion(deleteCount: finished.token.count,
                                                    text: replacement,
                                                    trailingKeyCode: nil,
                                                    trailingFlags: [])
        case .newline:
            // Return may have sent the message or run the command, and then
            // deleting and retyping would send a second one. The text is only
            // touched when it shows the word with a new line after it.
            let expected = finished.token + "\n"
            guard CommandBarSelectionReader.readTextBeforeCaret(length: expected.utf16.count) == expected
            else { return true }
            return TextSnippetService.postExpansion(deleteCount: finished.token.count + 1,
                                                    text: replacement,
                                                    trailingKeyCode: CGKeyCode(kVK_Return),
                                                    trailingFlags: finished.flags.intersection([.maskShift, .maskAlternate]))
        }
    }

    /// Weighs `word` against its spelling on every other enabled layout.
    private func outcome(for word: String, typedOn current: EnabledLayout,
                         language typedLanguage: String, at now: Date) -> Outcome {
        guard evidence.isReady(typedLanguage) else {
            warmUpEvidence()
            return .undecided
        }
        guard let currentGlyphs = glyphs(for: current.source, id: current.id) else { return .undecided }
        let sentence = eventLock.withLock { context }

        var best: Candidate?
        var kept: String?
        var doubtful = false
        for layout in enabledLayouts() where layout.id != current.id {
            guard let language = layout.language,
                  // Two layouts for one language spell the same words; the
                  // scorer would be weighing a language against itself.
                  language != typedLanguage, evidence.isReady(language),
                  let candidateGlyphs = glyphs(for: layout.source, id: layout.id),
                  let mapped = LayoutSwitcherSupport.table(from: currentGlyphs, to: candidateGlyphs)
                    .mapForward(word)
            else { continue }
            let lean = sentence.lean(toward: typedLanguage, over: language, at: now)
            switch scorer.judgement(typed: word, typedLanguage: typedLanguage,
                                    mapped: mapped, mappedLanguage: language, contextLean: lean) {
            case .rewrite(let core, let replacement, let verdict):
                guard verdict.margin > best?.verdict.margin ?? 0 else { continue }
                best = Candidate(layout: layout, language: language, word: core,
                                 replacement: replacement, verdict: verdict)
            case .keep(let core):
                kept = core
            case .undecided:
                doubtful = true
            }
        }
        if let best { return .rewrite(best) }
        if let kept, !doubtful { return .keep(word: kept) }
        return .undecided
    }

    private func resetBuffer() {
        eventLock.withLock { clearTypingState() }
    }

    /// The caret moved somewhere unknown, so nothing remembered about the text
    /// behind it holds: not the finished word, not a correction to take back,
    /// not a doubtful correction waiting for a second. Caller holds `eventLock`.
    private func clearTypingState() {
        typingBuffer.clear()
        lastAutomatic = nil
        gate.reset()
        activity &+= 1
    }
}
