// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Cast to TV in the island: a section and a Controls tile that only the
/// installed feature offers, both off until chosen, so installing it never
/// changes anyone's island on its own.
enum NotchTVCastTests {
    static func run(_ suite: TestSuite) {
        identityContracts(suite)
        sectionContracts(suite)
        tileContracts(suite)
        savedListContracts(suite)
        pageContracts(suite)
        heightContracts(suite)
    }

    /// A short page keeps a short island at every chosen size: a custom size
    /// only caps it, as for the timer, instead of stretching it the way the
    /// list pages grow to the size chosen.
    private static func heightContracts(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        for (camera, width) in [(CGFloat(0), 0.0), (32, 210)] {
            for height in [NotchSize.defaultHeight, NotchSize.heightRange.upperBound] {
                let geometry = NotchGeometry(screen: screen, safeAreaTop: camera, cameraWidth: width,
                                             layout: .custom, customWidth: NotchSize.defaultWidth, customHeight: height)
                let cast = geometry.expandedSize(module: .tvCast).height
                let list = geometry.expandedSize(module: .mixer).height
                suite.expect(cast <= geometry.headerTopInset + geometry.headerChromeHeight + NotchLayout.tvCastPageHeight,
                             "Cast to TV opens to its own page height in a \(Int(height))-point custom island: \(cast)")
                suite.expect(cast < list, "a list page grows to the custom height and Cast to TV does not: \(cast) vs \(list)")
            }
        }
    }

    /// A fresh domain holding the island's registered lists, as a new setup
    /// reads them. Registration itself is shared by the whole test process.
    private static func withFreshDefaults(_ suite: TestSuite, _ body: (UserDefaults) -> Void) {
        let domain = "com.vorssaint.tests.notch-tv-cast.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: domain) else {
            suite.expect(false, "the Cast to TV island suite can be created")
            return
        }
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(Defaults.registeredDefaults[DefaultsKey.notchHiddenModules], forKey: DefaultsKey.notchHiddenModules)
        defaults.set(NotchControlItem.defaultHidden, forKey: DefaultsKey.notchHiddenControls)
        body(defaults)
    }

    private static func identityContracts(_ suite: TestSuite) {
        suite.expect(NotchModule.tvCast.symbol == AppFeature.tvCast.symbolName
                     && NotchModule.tvCast.shortcutKey == "y"
                     && NotchModule.allCases.filter { $0.shortcutKey == "y" } == [.tvCast],
                     "the section wears the feature's TV and opens with its own Option-Command-Y")
        for language in AppLanguage.allCases {
            suite.expect(NotchModule.tvCast.title(language) == FeatureStrings.tvCast(language).pageTitle,
                         "the section is named as the feature's page (\(language.rawValue))")
        }
        let language = L10n.shared.language
        suite.expect(FeatureStrings.notchEditor(language).summary(.tvCast) == FeatureStrings.tvCast(language).hubDescription,
                     "the Sections list describes it in the feature's own words")
    }

    private static func sectionContracts(_ suite: TestSuite) {
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchHiddenModules] as? String == NotchModule.tvCast.rawValue,
                     "a setup that never hid a section starts with Cast to TV unchecked")
        withFreshDefaults(suite) { defaults in
            suite.expect(!NotchModule.tvCast.isAvailable(in: defaults)
                         && !NotchSupport.modules(in: defaults).contains(.tvCast),
                         "the section waits for Cast to TV to be installed")
            defaults.set(true, forKey: AppFeature.tvCast.availabilityKey)
            suite.expect(NotchModule.tvCast.isAvailable(in: defaults)
                         && !NotchSupport.modules(in: defaults).contains(.tvCast),
                         "installing Cast to TV offers the section unchecked, out of the island")
            defaults.set("", forKey: DefaultsKey.notchHiddenModules)
            suite.expect(NotchSupport.modules(in: defaults).last == .tvCast,
                         "chosen, it joins the island after every earlier section")
            defaults.set("music,controls", forKey: DefaultsKey.notchModuleOrder)
            suite.expect(NotchSupport.modules(in: defaults) == [.music, .controls, .tvCast],
                         "a saved order keeps its sections and gains this one at its end")
            defaults.set(false, forKey: AppFeature.tvCast.availabilityKey)
            suite.expect(!NotchSupport.modules(in: defaults).contains(.tvCast),
                         "uninstalling Cast to TV takes its section away")
        }
    }

    private static func tileContracts(_ suite: TestSuite) {
        suite.expect(NotchControlItem.defaultHidden.split(separator: ",").contains("tvCast")
                     && NotchControlItem.tvCast.setupRequirement == .page(.tvCast, feature: .tvCast)
                     && NotchControlItem.tvCast.symbol == NotchModule.tvCast.symbol
                     && !NotchControlItem.tvCast.isLevel,
                     "the tile is hidden by default and, like the mixer's, leads to its section or the feature")
        withFreshDefaults(suite) { defaults in
            defaults.set(true, forKey: AppFeature.tvCast.availabilityKey)
            suite.expect(!NotchControlItem.tvCast.isAvailable(in: defaults),
                         "the tile waits for its section, as the mixer's does")
            defaults.set("", forKey: DefaultsKey.notchHiddenModules)
            suite.expect(NotchControlItem.tvCast.isAvailable(in: defaults)
                         && !NotchSupport.controls(in: defaults).contains(.tvCast),
                         "with the section shown, the tile still stays out until chosen")
            defaults.set("", forKey: DefaultsKey.notchHiddenControls)
            suite.expect(NotchSupport.controls(in: defaults).contains(.tvCast)
                         && NotchQuickAction(id: NotchQuickAction.control(.tvCast).id) == .control(.tvCast)
                         && NotchQuickAction.optionalActions.contains(.control(.tvCast))
                         && NotchQuickAction.module(.tvCast).isAvailable(in: defaults),
                         "chosen, the tile shows among the controls and can float beside the island")
            defaults.set(false, forKey: AppFeature.tvCast.availabilityKey)
            suite.expect(!NotchControlItem.tvCast.isAvailable(in: defaults)
                         && !NotchSupport.controls(in: defaults).contains(.tvCast)
                         && !NotchQuickAction.control(.tvCast).isAvailable(in: defaults),
                         "uninstalling Cast to TV leaves no tile behind")
        }
    }

    /// A hidden list saved before the section existed must not show it.
    private static func savedListContracts(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.notch-tv-cast-saved.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: domain) else {
            suite.expect(false, "the saved hidden list suite can be created")
            return
        }
        defer { defaults.removePersistentDomain(forName: domain) }
        let hiddenKey = DefaultsKey.notchHiddenModules
        Defaults.hideTVCastSectionUntilInstalled(in: defaults, domainName: domain)
        suite.expect(defaults.persistentDomain(forName: domain)?[hiddenKey] == nil,
                     "a setup that never hid a section keeps the registered default")
        defaults.set("music", forKey: hiddenKey)
        Defaults.hideTVCastSectionUntilInstalled(in: defaults, domainName: domain)
        Defaults.hideTVCastSectionUntilInstalled(in: defaults, domainName: domain)
        suite.expect(defaults.string(forKey: hiddenKey) == "music,tvCast",
                     "a hidden list saved before the section existed gains it, once")
        defaults.set(true, forKey: AppFeature.tvCast.availabilityKey)
        defaults.set("music", forKey: hiddenKey)
        Defaults.hideTVCastSectionUntilInstalled(in: defaults, domainName: domain)
        suite.expect(defaults.string(forKey: hiddenKey) == "music",
                     "once Cast to TV is installed, showing its section is the person's choice")
        defaults.set(false, forKey: AppFeature.tvCast.availabilityKey)
        Defaults.hideTVCastSectionUntilInstalled(in: defaults, domainName: domain)
        suite.expect(defaults.string(forKey: hiddenKey) == "music",
                     "that choice survives an uninstall")
        let launch = source("Sources/Vorssaint/Core/Defaults.swift")
        suite.expect(launch.contains("hideTVCastSectionUntilInstalled(in: defaults)\n        defaults.register(defaults: registeredDefaults)"),
                     "every launch keeps the section out of a saved list until the feature is first installed")
    }

    private static func pageContracts(_ suite: TestSuite) {
        let controls = source("Sources/Vorssaint/UI/Notch/NotchControlsView.swift")
        let service = source("Sources/Vorssaint/Services/Notch/NotchService.swift")
        let island = source("Sources/Vorssaint/UI/Notch/NotchView.swift")
        suite.expect(controls.contains("NotchActionTile(symbol: item.symbol, title: item.title(l10n)) { service.select(.tvCast) }")
                     && service.contains("case .tvCast: select(.tvCast)")
                     && island.contains("case .tvCast: NotchTVCastView()"),
                     "the tile and its floating button open the Cast to TV section, as the mixer's open the mixer")
        let page = source("Sources/Vorssaint/UI/Notch/NotchTVCastView.swift")
        let read = "NSPasteboard.general.string(forType: .string)"
        let press = page.range(of: "private func playCopiedLink()")
        let reading = page.range(of: read)
        suite.expect(page.components(separatedBy: "NSPasteboard").count == 2
                     && press != nil && reading != nil
                     && (press?.upperBound ?? page.endIndex) < (reading?.lowerBound ?? page.startIndex),
                     "the page reads the pasteboard only when Play Copied Link is pressed, never unasked")
        suite.expect(page.contains("TVCastService.shared") && !page.contains("TVCastService(")
                     && page.contains(".onAppear { service.reload() }"),
                     "the page shares the feature's one service and refreshes its TVs as it appears")
    }

    private static func source(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }
}
