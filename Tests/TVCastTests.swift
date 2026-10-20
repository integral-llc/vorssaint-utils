// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum TVCastTests {
    static func run(_ suite: TestSuite) {
        videoArgumentRules(suite)
        rejectedVideoRules(suite)
        pairingCodeRules(suite)
        deviceRules(suite)
        defaultNameRules(suite)
        pairedNameRules(suite)
        pickerRules(suite)
        changedDeviceRules(suite)
        renamingRules(suite)
        removingRules(suite)
        duplicateRules(suite)
        printedIDRules(suite)
        settledPairingRules(suite)
        cacheRestoreRules(suite)
        pairingMergeRules(suite)
        commandLinePathRules(suite)
        commandLineImportRules(suite)
        commandLineMergeRules(suite)
        commandLineFidelityRules(suite)
        failureRules(suite)
        networkFailureRules(suite)
        serviceSourceRules(suite)
    }

    // MARK: Fixtures

    /// A code-paired entry as ytcast writes it. Each TV gets a screen of its
    /// own unless a test names one, so two entries share a screen on purpose.
    private static func entry(_ deviceID: String, token: String = "t", used: Bool = false,
                              screen: String? = nil, name: String = "n") -> String {
        let screenID = screen ?? "screen-\(deviceID)"
        return "{\"Device\": null, \"Remote\": {\"ScreenId\": \"\(screenID)\", \"DeviceId\": \"\(deviceID)\", "
            + "\"LoungeToken\": \"\(token)\", \"ScreenName\": \"\(name)\"}, \"LastUsed\": \(used)}"
    }

    private static func discovered(_ serviceName: String, name: String, screen: String = "s") -> String {
        "{\"Device\": {\"UniqueServiceName\": \"\(serviceName)\", \"FriendlyName\": \"\(name)\"}, "
            + "\"Remote\": {\"ScreenId\": \"\(screen)\"}, \"LastUsed\": false}"
    }

    private static func data(_ entries: [String]) -> Data { Data("[\(entries.joined(separator: ","))]".utf8) }

    private static func parse(_ data: Data?) -> [[String: Any]]? {
        data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] }
    }

    /// Every entry's id, in file order: a discovered TV's service name, else
    /// the pairing's device id.
    private static func ids(_ data: Data?) -> [String]? {
        parse(data)?.map { entry in
            ((entry["Device"] as? [String: Any])?["UniqueServiceName"] as? String)
                ?? ((entry["Remote"] as? [String: Any])?["DeviceId"] as? String) ?? "?"
        }
    }

    private static func remoteField(_ field: String, of id: String, in data: Data?) -> String? {
        let remotes = parse(data)?.compactMap { $0["Remote"] as? [String: Any] } ?? []
        return remotes.first { $0["DeviceId"] as? String == id }?[field] as? String
    }

    /// A pairing's line as ytcast v1.4.1 prints it, `%.8s %-15s %-30q %s`,
    /// checked against Go's own fmt: "unknown" padded to 15, then a space.
    private static func printedLine(_ printedID: String, _ name: String, _ info: String = "") -> String {
        let quoted = "\"\(name)\""
        return printedID + " unknown" + String(repeating: " ", count: 9) + quoted
            + String(repeating: " ", count: max(0, 30 - quoted.count)) + " " + info
    }

    private static let richCache = Data("""
    [{"Device": null,
      "Remote": {"ScreenId": "s1", "LoungeToken": "tok", "Expiration": 1790000000123, "SId": "sid",
                 "GSessionId": "gs", "DeviceId": "dev-code", "ScreenName": "Living room", "Future": [1, {"x": true}]},
      "LastUsed": true, "Extra": {"n": 10000000000}},
     {"Device": {"UniqueServiceName": "uuid:abc", "FriendlyName": "Bedroom",
                 "Wakeup": {"Mac": "aa:bb", "Timeout": 10000000000}},
      "Remote": null, "LastUsed": false}]
    """.utf8)

    // MARK: Video argument

    private static func videoArgumentRules(_ suite: TestSuite) {
        let id = "dQw4w9WgXcQ"
        let canonical = "https://www.youtube.com/watch?v=\(id)"
        let accepted: [(String, String)] = [
            ("https://www.youtube.com/watch?v=\(id)", canonical),
            ("https://youtu.be/\(id)?t=42", canonical + "&t=42"),
            ("https://youtu.be/\(id)?si=abcdef", canonical),
            ("https://www.youtube.com/shorts/\(id)", canonical),
            ("https://www.youtube.com/live/\(id)?feature=share", canonical),
            ("https://www.youtube.com/embed/\(id)", canonical),
            ("https://www.youtube-nocookie.com/embed/\(id)", canonical),
            ("https://music.youtube.com/watch?v=\(id)&list=RDAMVM\(id)", canonical),
            ("https://m.youtube.com/watch?v=\(id)", canonical),
            ("http://youtube.com/watch?v=\(id)", canonical),
            ("https://WWW.YouTube.com/watch?v=\(id)", canonical),
            ("youtu.be/\(id)", canonical),
            ("www.youtube.com/watch?v=\(id)", canonical),
            ("https://www.youtube.com/watch?v=\(id)&t=1m30s", canonical + "&t=1m30s"),
            ("https://www.youtube.com/watch?v=\(id)&t=1h2m3s", canonical + "&t=1h2m3s"),
            ("https://www.youtube.com/watch?v=\(id)&t=90s", canonical + "&t=90s"),
            ("https://www.youtube.com/watch?v=\(id)&t=abc", canonical),
            ("https://www.youtube.com/watch?v=\(id)&t=1x", canonical),
            ("https://www.youtube.com/watch?v=\(id)&t=", canonical),
            ("  \n https://youtu.be/\(id) \t", canonical),
            (id, canonical),
            ("  \(id)\n", canonical),
            ("-abcdefghij", "https://www.youtube.com/watch?v=-abcdefghij"),
            ("_-_-_-_-_-_", "https://www.youtube.com/watch?v=_-_-_-_-_-_"),
        ]
        for (input, expected) in accepted {
            suite.expectEqual(TVCastSupport.videoArgument(from: input), expected, "video argument for \(input)")
        }
    }

    private static func rejectedVideoRules(_ suite: TestSuite) {
        let id = "dQw4w9WgXcQ"
        let rejected = [
            "", "   \n", "short", "dQw4w9WgXcQx", "dQw4w9WgXc",
            "https://www.youtube.com/watch?v=short",
            "https://www.youtube.com/playlist?list=PLabcdefghijklmnop",
            "https://www.youtube.com/watch?list=PLabcdefghijklmnop",
            "https://vimeo.com/watch?v=\(id)",
            "https://notyoutube.com/watch?v=\(id)",
            "https://youtube.com.evil.example/watch?v=\(id)",
            "ftp://youtu.be/\(id)",
            "file:///tmp/\(id)",
            "https://www.youtube.com/",
            "https://youtu.be/",
            "https://www.youtube.com/channel/\(id)",
        ]
        for input in rejected {
            suite.expect(TVCastSupport.videoArgument(from: input) == nil, "not a video: \(input)")
        }
    }

    // MARK: Pairing code and arguments

    private static func pairingCodeRules(_ suite: TestSuite) {
        suite.expectEqual(TVCastSupport.pairingCode(from: "123 456 789 012"), "123456789012", "spaces are dropped")
        suite.expectEqual(TVCastSupport.pairingCode(from: " 123-456-789-012\n"), "123456789012",
                          "dashes are dropped")
        suite.expectEqual(TVCastSupport.pairingCode(from: "12345678"), "12345678", "shortest accepted code")
        suite.expectEqual(TVCastSupport.pairingCode(from: "1234567890123456"), "1234567890123456",
                          "longest accepted code")
        for bad in ["", "1234567", "12345678901234567", "1234 5678 90ab", "abc", "1234567\u{0663}89"] {
            suite.expect(TVCastSupport.pairingCode(from: bad) == nil, "not a code: \(bad)")
        }
        let canonical = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        suite.expectEqual(TVCastSupport.pairArguments(code: "123456789012"), ["-pair=123456789012"],
                          "pair arguments")
        suite.expectEqual(TVCastSupport.castArguments(deviceID: "tv-1", video: "-abcdefghij"),
                          ["-d=tv-1", "--", "-abcdefghij"], "cast arguments end flag parsing")
        suite.expectEqual(TVCastSupport.castArguments(deviceID: "-dash", video: canonical),
                          ["-d=-dash", "--", canonical], "a device id starting with a dash stays attached")
    }

    // MARK: Devices

    private static func deviceRules(_ suite: TestSuite) {
        let cache = """
        [
          {"Device": null,
           "Remote": {"ScreenId": "s1", "Name": "YouTube on TV", "LoungeToken": "tok", "Expiration": 1790000000000,
                      "SId": "sid", "GSessionId": "gs", "DeviceId": "dev-code", "ScreenName": "Living room"},
           "LastUsed": false},
          {"Device": {"UniqueServiceName": "uuid:abc::urn:dial", "Location": "http://10.0.0.5:8008/dd.xml",
                      "ApplicationUrl": "http://10.0.0.5:8008/apps/", "FriendlyName": "Bedroom",
                      "Wakeup": {"Mac": "aa:bb", "Timeout": 10000000000}},
           "Remote": null, "LastUsed": true}
        ]
        """
        suite.expectEqual(TVCastSupport.devices(fromCache: Data(cache.utf8)), [
            TVCastDevice(id: "uuid:abc::urn:dial", name: "Bedroom", pairedWithCode: false, lastUsed: true),
            TVCastDevice(id: "dev-code", name: "Living room", pairedWithCode: true, lastUsed: false),
        ], "two-entry cache, last used first")
        suite.expectEqual(TVCastSupport.devices(fromCache: nil), [], "no cache")
        suite.expectEqual(TVCastSupport.devices(fromCache: Data()), [], "empty cache")
        suite.expectEqual(TVCastSupport.devices(fromCache: Data("{not json".utf8)), [], "malformed cache")
        suite.expectEqual(TVCastSupport.devices(fromCache: Data("{\"a\":1}".utf8)), [], "wrong top-level type")
        let odd = """
        [{"Device": null, "Remote": null, "LastUsed": false},
         {"Device": null, "Remote": {"DeviceId": "", "ScreenName": "No id"}},
         {"Device": {"UniqueServiceName": "", "FriendlyName": "No id either"}, "Remote": null},
         {"Device": null, "Remote": {"DeviceId": "nameless", "ScreenName": ""}},
         {"Device": {"UniqueServiceName": "uuid:both", "FriendlyName": "Discovered"},
          "Remote": {"DeviceId": "ignored", "ScreenName": "ignored"}}]
        """
        suite.expectEqual(TVCastSupport.devices(fromCache: Data(odd.utf8)), [
            TVCastDevice(id: "uuid:both", name: "Discovered", pairedWithCode: false, lastUsed: false),
            TVCastDevice(id: "nameless", name: "nameless", pairedWithCode: true, lastUsed: false),
        ], "entries without an id are skipped, an empty name falls back to the id, Device wins over Remote")
        let sortable = """
        [{"Device": {"UniqueServiceName": "b", "FriendlyName": "TV 10"}, "Remote": null},
         {"Device": {"UniqueServiceName": "c", "FriendlyName": "TV 2"}, "Remote": null},
         {"Device": {"UniqueServiceName": "z", "FriendlyName": "Same"}, "Remote": null},
         {"Device": {"UniqueServiceName": "a", "FriendlyName": "Same"}, "Remote": null},
         {"Device": {"UniqueServiceName": "d", "FriendlyName": "Zed"}, "Remote": null, "LastUsed": true}]
        """
        suite.expectEqual(TVCastSupport.devices(fromCache: Data(sortable.utf8)).map(\.id), ["d", "a", "z", "c", "b"],
                          "last used, then natural name order (TV 2 before TV 10), then id")
    }

    // MARK: Names

    private static func defaultNameRules(_ suite: TestSuite) {
        suite.expectEqual(TVCastSupport.defaultName(avoiding: []), "Apple TV", "the first TV is Apple TV")
        suite.expectEqual(TVCastSupport.defaultName(avoiding: ["Living room"]), "Apple TV",
                          "other names leave it free")
        suite.expectEqual(TVCastSupport.defaultName(avoiding: ["Apple TV"]), "Apple TV 2", "a taken name is numbered")
        suite.expectEqual(TVCastSupport.defaultName(avoiding: ["Apple TV", "Apple TV 2", "Apple TV 3"]), "Apple TV 4",
                          "numbering skips every taken number")
        suite.expectEqual(TVCastSupport.defaultName(avoiding: ["Apple TV", "Apple TV 3"]), "Apple TV 2",
                          "the first free number wins")
        suite.expectEqual(TVCastSupport.defaultName(avoiding: ["Apple TV 2"]), "Apple TV",
                          "the plain name is used while it is free")
        suite.expectEqual(TVCastSupport.defaultName(avoiding: ["  apple tv ", "APPLE TV 2"]), "Apple TV 3",
                          "case and surrounding spaces do not make a name different")
    }

    private static func pairedNameRules(_ suite: TestSuite) {
        func name(_ typed: String, _ entries: [String], id: String = "new") -> String {
            TVCastSupport.pairedName(typed: typed, for: id, inCache: data(entries))
        }
        let reported = entry("new", name: "Kitchen")
        suite.expectEqual(name("  Den \n", [reported]), "Den", "a typed name wins, trimmed")
        suite.expectEqual(name("", [reported]), "Kitchen", "a blank name takes the one YouTube reported")
        suite.expectEqual(name(" ", [entry("new", name: "  Kitchen ")]), "Kitchen", "the reported name is trimmed")
        suite.expectEqual(name("", [entry("a", name: " kitchen"), reported]), "Kitchen 2",
                          "a reported name another TV has is numbered")
        suite.expectEqual(name("", [entry("a", name: "Kitchen"), entry("b", name: "Kitchen 2"), reported]),
                          "Kitchen 3", "numbering skips taken numbers")
        suite.expectEqual(name("", [entry("new", name: "new")]), "Apple TV",
                          "ytcast's stand-in name, the id itself, counts as no name")
        suite.expectEqual(name("", [entry("new", name: "")]), "Apple TV", "an empty reported name counts as none")
        suite.expectEqual(name("", [entry("a", name: "Apple TV"), entry("new", name: "new")]), "Apple TV 2",
                          "the default is numbered against the other TVs")
        suite.expectEqual(name("", [entry("new", name: "Apple TV")]), "Apple TV",
                          "the paired TV's own name does not count as taken")
        suite.expectEqual(name("", [entry("a", name: "Kitchen")], id: "gone"), "Apple TV",
                          "a TV missing from the cache gets the default")
    }

    private static func pickerRules(_ suite: TestSuite) {
        let pickable = [
            TVCastDevice(id: "a", name: "A", pairedWithCode: true, lastUsed: false),
            TVCastDevice(id: "b", name: "B", pairedWithCode: true, lastUsed: true),
        ]
        suite.expectEqual(TVCastSupport.selectedDeviceID("a", in: pickable), "a", "a listed pick is kept")
        suite.expectEqual(TVCastSupport.selectedDeviceID(nil, in: pickable), "b", "no pick falls to the last used TV")
        suite.expectEqual(TVCastSupport.selectedDeviceID("gone", in: pickable), "b",
                          "a removed pick falls to the last used TV")
        suite.expectEqual(TVCastSupport.selectedDeviceID(nil, in: [pickable[0]]), "a", "with none last used, the first")
        suite.expect(TVCastSupport.selectedDeviceID("a", in: []) == nil, "no TVs, no selection")
    }

    // MARK: Cache edits

    private static func changedDeviceRules(_ suite: TestSuite) {
        let base = data([entry("a"), entry("b")])
        suite.expectEqual(TVCastSupport.changedDeviceID(before: base,
                                                        after: data([entry("a"), entry("b"), entry("c")])),
                          "c", "a new entry")
        suite.expectEqual(TVCastSupport.changedDeviceID(before: nil, after: data([entry("c")])), "c",
                          "first ever entry")
        suite.expectEqual(TVCastSupport.changedDeviceID(before: base,
                                                        after: data([entry("a"), entry("b", token: "new")])),
                          "b", "a replaced Remote on the same id")
        suite.expect(TVCastSupport.changedDeviceID(
            before: base, after: data([entry("a", used: true), entry("b")])) == nil,
                     "a LastUsed-only change is not a pairing")
        suite.expect(TVCastSupport.changedDeviceID(before: base, after: base) == nil, "nothing changed")
        suite.expect(TVCastSupport.changedDeviceID(
            before: base, after: data([entry("a", token: "x"), entry("b", token: "y")])) == nil,
                     "two changes are ambiguous")
        suite.expect(TVCastSupport.changedDeviceID(
            before: base, after: data([entry("a"), entry("b"), entry("c"), entry("d")])) == nil,
                     "two new entries are ambiguous")
        suite.expect(TVCastSupport.changedDeviceID(before: base, after: nil) == nil, "no cache after")
    }

    private static func renamingRules(_ suite: TestSuite) {
        let renamed = TVCastSupport.renaming("dev-code", to: "  Den  ", inCache: richCache)
        let entries = parse(renamed)
        let remote = entries?.first?["Remote"] as? [String: Any]
        suite.expectEqual(remote?["ScreenName"] as? String, "Den", "the trimmed name is written")
        suite.expectEqual((remote?["Expiration"] as? NSNumber)?.int64Value, 1_790_000_000_123,
                          "Expiration stays exact")
        suite.expect((remote?["Expiration"] as? NSNumber).map { !CFNumberIsFloatType($0) } == true,
                     "Expiration stays an integer")
        suite.expectEqual(remote?["LoungeToken"] as? String, "tok", "other Remote fields are kept")
        suite.expectEqual((remote?["Future"] as? [Any])?.count, 2, "unknown Remote fields are kept")
        suite.expectEqual(entries?.first?["LastUsed"] as? Bool, true, "LastUsed is kept")
        let extra = entries?.first?["Extra"] as? [String: Any]
        suite.expectEqual((extra?["n"] as? NSNumber)?.int64Value, 10_000_000_000, "unknown top-level fields are kept")
        let wakeup = (entries?.last?["Device"] as? [String: Any])?["Wakeup"] as? [String: Any]
        suite.expectEqual((wakeup?["Timeout"] as? NSNumber)?.int64Value, 10_000_000_000, "Wakeup.Timeout stays exact")
        suite.expect((wakeup?["Timeout"] as? NSNumber).map { !CFNumberIsFloatType($0) } == true,
                     "Wakeup.Timeout stays an integer")
        suite.expectEqual(entries?.count, 2, "no entry is lost by a rename")
        let renamedText = renamed.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        suite.expect(!renamedText.contains("1.79") && !renamedText.contains("e+"),
                     "integers are not serialized as floats: \(renamedText)")
        suite.expect(TVCastSupport.renaming("uuid:abc", to: "Den", inCache: richCache) == nil,
                     "a discovered TV cannot be renamed")
        suite.expect(TVCastSupport.renaming("dev-code", to: "  \n", inCache: richCache) == nil,
                     "an empty name is refused")
        suite.expect(TVCastSupport.renaming("nope", to: "Den", inCache: richCache) == nil,
                     "an unknown id is refused")
        suite.expect(TVCastSupport.renaming("dev-code", to: "Den", inCache: Data("oops".utf8)) == nil,
                     "malformed data is refused")
    }

    private static func removingRules(_ suite: TestSuite) {
        let removed = parse(TVCastSupport.removing("dev-code", fromCache: richCache))
        suite.expectEqual(removed?.count, 1, "one entry is dropped")
        suite.expectEqual(((removed?.first?["Device"] as? [String: Any])?["UniqueServiceName"]) as? String,
                          "uuid:abc", "the other entry is kept")
        let keptWakeup = ((removed?.first?["Device"] as? [String: Any])?["Wakeup"] as? [String: Any])?["Timeout"]
        suite.expectEqual((keptWakeup as? NSNumber)?.int64Value, 10_000_000_000, "kept entries are untouched")
        let discoveredGone = parse(TVCastSupport.removing("uuid:abc", fromCache: richCache))
        suite.expectEqual(discoveredGone?.count, 1, "a discovered TV can be forgotten too")
        suite.expect(TVCastSupport.removing("nope", fromCache: richCache) == nil, "unknown id gives nil")
        suite.expect(TVCastSupport.removing("a", fromCache: Data("oops".utf8)) == nil, "malformed data gives nil")
        suite.expectEqual(parse(TVCastSupport.removing("a", fromCache: data([entry("a")])))?.count, 0,
                          "the last entry can go")
    }

    // MARK: Pairing again

    private static func duplicateRules(_ suite: TestSuite) {
        let cache = data([
            entry("old", used: true, screen: "S1"), entry("new", screen: "S1"), entry("x", screen: "S2"),
            discovered("uuid:d", name: "Bedroom", screen: "S1"), entry("old2", screen: "S1"),
        ])
        suite.expectEqual(ids(TVCastSupport.droppingDuplicates(of: "new", inCache: cache)), ["new", "x", "uuid:d"],
                          "other code-paired entries on the same screen go, the rest stay in order")
        let alone = data([entry("new", screen: "S1"), entry("x", screen: "S2")])
        suite.expectEqual(TVCastSupport.droppingDuplicates(of: "new", inCache: alone), alone,
                          "no duplicate leaves the bytes as they were")
        let noScreen = Data("[{\"Device\": null, \"Remote\": {\"DeviceId\": \"new\"}}, \(entry("x"))]".utf8)
        suite.expectEqual(TVCastSupport.droppingDuplicates(of: "new", inCache: noScreen), noScreen,
                          "a pairing without a screen id has nothing to compare")
        let unscreened = "{\"Device\": null, \"Remote\": {\"DeviceId\": \"y\"}}"
        let screenless = data([entry("new", screen: "S1"), unscreened])
        suite.expectEqual(ids(TVCastSupport.droppingDuplicates(of: "new", inCache: screenless)), ["new", "y"],
                          "an entry without a screen id is not a duplicate")
        suite.expect(TVCastSupport.droppingDuplicates(of: "uuid:d", inCache: cache) == nil,
                     "a discovered entry is not a pairing")
        suite.expect(TVCastSupport.droppingDuplicates(of: "gone", inCache: cache) == nil, "an unknown id gives nil")
        suite.expect(TVCastSupport.droppingDuplicates(of: "new", inCache: Data("oops".utf8)) == nil,
                     "malformed data gives nil")
    }

    private static func printedIDRules(_ suite: TestSuite) {
        suite.expectEqual(printedLine("a1b2c3d4", "Living room"),
                          "a1b2c3d4 unknown         \"Living room\"" + String(repeating: " ", count: 18),
                          "the fixture is ytcast's line")
        let line = printedLine("a1b2c3d4", "Living room")
        suite.expectEqual(TVCastSupport.printedPairingID(in: line + "\n"), "a1b2c3d4", "the printed id")
        suite.expectEqual(TVCastSupport.printedPairingID(in: printedLine("abc", "Den", "lastused")), "abc",
                          "a short id is printed whole")
        suite.expectEqual(TVCastSupport.printedPairingID(in: "noise\n" + line + "\nmore noise\n"), "a1b2c3d4",
                          "other lines are skipped")
        let discoveredLine = "a1b2c3d4 10.0.0.5        \"Bedroom\"" + String(repeating: " ", count: 22)
        for output in ["", "ytcast: ConnectWithCode: 404 Not Found\n", discoveredLine, " " + line] {
            suite.expect(TVCastSupport.printedPairingID(in: output) == nil, "no pairing line: \(output)")
        }
        let cache = data([entry("a1b2c3d4-0000-1111"), entry("ffff0000-2222"), entry("abc"), entry("abcdef1234")])
        suite.expectEqual(TVCastSupport.pairedDeviceID(printedIn: line, cache: cache), "a1b2c3d4-0000-1111",
                          "the one code-paired TV whose id starts with the printed one")
        suite.expectEqual(TVCastSupport.pairedDeviceID(printedIn: printedLine("abc", "Den"), cache: cache), "abc",
                          "a short printed id is the whole id, not the start of a longer one")
        let twins = data([entry("a1b2c3d4-0000-1111"), entry("a1b2c3d4-9999")])
        suite.expect(TVCastSupport.pairedDeviceID(printedIn: line, cache: twins) == nil,
                     "two ids with the same start are ambiguous")
        let prefixed = data([entry("uuid:a1b2c3d4-x"), discovered("uuid:a1b2c3d4-dial", name: "Bedroom")])
        suite.expectEqual(TVCastSupport.pairedDeviceID(printedIn: line, cache: prefixed), "uuid:a1b2c3d4-x",
                          "ytcast prints an id without its uuid: prefix, and only pairings count")
        suite.expect(TVCastSupport.pairedDeviceID(printedIn: "", cache: cache) == nil, "nothing printed, no id")
        suite.expect(TVCastSupport.pairedDeviceID(printedIn: line, cache: nil) == nil, "no cache, no id")
    }

    private static func settledPairingRules(_ suite: TestSuite) {
        let again = data([
            entry("old", used: true, screen: "S1", name: "Living room"),
            entry("new", screen: "S1", name: "Living room"), entry("x", name: "Den"),
        ])
        let settled = TVCastSupport.settledPairing(of: "new", typedName: " ", inCache: again)
        suite.expectEqual(settled?.name, "Living room",
                          "the old entry goes before naming, so the TV keeps its name without a number")
        suite.expectEqual(ids(settled?.cache), ["new", "x"], "the dead duplicate is gone")
        suite.expectEqual(remoteField("ScreenName", of: "new", in: settled?.cache), "Living room", "the name is saved")
        let typed = TVCastSupport.settledPairing(of: "new", typedName: "Den", inCache: again)
        suite.expectEqual(typed?.name, "Den", "a typed name is used as typed")
        suite.expectEqual(remoteField("ScreenName", of: "new", in: typed?.cache), "Den", "the typed name is saved")
        suite.expect(TVCastSupport.settledPairing(of: "gone", typedName: "Den", inCache: again) == nil,
                     "a TV missing from the cache settles nothing")
    }

    // MARK: Cache repair

    private static func cacheRestoreRules(_ suite: TestSuite) {
        func repaired(_ snapshot: Data?, _ after: Data?, pairing output: String? = nil) -> Data? {
            TVCastSupport.repairedCache(snapshot: snapshot, after: after, pairingOutput: output)
        }
        let snapshot = data([entry("a", token: "ta"), entry("b", token: "tb")])
        let sent = data([entry("a", token: "ta2", used: true), entry("b", token: "tb")])
        let truncated = sent.prefix(sent.count / 2)
        suite.expectEqual(ids(repaired(snapshot, truncated)), ["a", "b"], "a cut-off file gets the snapshot back")
        suite.expectEqual(remoteField("LoungeToken", of: "a", in: repaired(snapshot, truncated)), "ta",
                          "the snapshot comes back as it was")
        suite.expectEqual(ids(repaired(snapshot, Data())), ["a", "b"], "an emptied file gets the snapshot back")
        suite.expectEqual(ids(repaired(snapshot, Data("null".utf8))), ["a", "b"],
                          "null in place of a list gets the snapshot back")
        suite.expectEqual(ids(repaired(snapshot, nil)), ["a", "b"], "a deleted file gets the snapshot back")
        suite.expect(repaired(snapshot, sent) == nil, "a send's readable result is left as ytcast wrote it")
        suite.expect(repaired(snapshot, data([entry("a")])) == nil, "only a pairing's result is merged")
        suite.expect(repaired(nil, Data("null".utf8)) == nil && repaired(Data(), Data("null".utf8)) == nil,
                     "null after a failed run on an empty snapshot stays as is")
        suite.expect(repaired(Data("oops".utf8), Data("null".utf8)) == nil, "an unreadable snapshot restores nothing")
        suite.expectEqual(ids(repaired(Data("[]".utf8), Data("null".utf8))), [],
                          "an empty list comes back as an empty list")
    }

    private static func pairingMergeRules(_ suite: TestSuite) {
        func repaired(_ snapshot: Data?, _ after: Data?, _ output: String = "") -> Data? {
            TVCastSupport.repairedCache(snapshot: snapshot, after: after, pairingOutput: output)
        }
        let snapshot = data([entry("a"), entry("b")])
        let printed = printedLine("c0ffee00", "Kitchen") + "\n"
        suite.expect(repaired(snapshot, data([entry("a"), entry("b"), entry("c0ffee00-11", name: "Kitchen")]),
                              printed) == nil, "a normal pairing is left untouched")
        suite.expect(repaired(snapshot, data([entry("a", token: "new"), entry("b")]), printed) == nil,
                     "a pairing that replaced a TV on its own id is left untouched")
        let alone = data([entry("c0ffee00-11", name: "Kitchen")])
        suite.expectEqual(ids(repaired(snapshot, alone, printed)), ["c0ffee00-11", "a", "b"],
                          "a pairing that dropped the other TVs gets them back")
        let full = data([entry("c0ffee00-11", token: "tc"), entry("a"), entry("b")])
        let cutAfterPairing = full.prefix(Data(entry("c0ffee00-11", token: "tc").utf8).count + 3)
        suite.expectEqual(ids(repaired(snapshot, cutAfterPairing, printed)), ["a", "b", "c0ffee00-11"],
                          "a cut-off file keeps the printed pairing when it survived whole")
        let survived = repaired(snapshot, cutAfterPairing, printed)
        suite.expectEqual(remoteField("LoungeToken", of: "c0ffee00-11", in: survived), "tc",
                          "the surviving pairing keeps its token")
        let cutInsidePairing = full.prefix(20)
        suite.expectEqual(ids(repaired(snapshot, cutInsidePairing, printed)), ["a", "b"],
                          "a pairing cut in half is lost, the snapshot is not")
        suite.expectEqual(ids(repaired(snapshot, cutAfterPairing, "")), ["a", "b"],
                          "without a printed line nothing names the pairing")
        let replaced = data([entry("a", token: "fresh"), entry("b")])
        let cutReplaced = replaced.prefix(Data(entry("a", token: "fresh").utf8).count + 2)
        let rePaired = repaired(snapshot, cutReplaced, printedLine("a", "n"))
        suite.expectEqual(remoteField("LoungeToken", of: "a", in: rePaired), "fresh",
                          "a surviving re-pairing replaces the snapshot's entry")
        suite.expectEqual(ids(rePaired), ["b", "a"], "and is not listed twice")
    }

    // MARK: Command line import

    private static func lastUsed(_ id: String, in data: Data?) -> Bool? {
        parse(data)?.first { ($0["Remote"] as? [String: Any])?["DeviceId"] as? String == id }?["LastUsed"] as? Bool
    }

    private static func commandLinePathRules(_ suite: TestSuite) {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        suite.expectEqual(TVCastSupport.commandLineCacheURL(home: home).path,
                          "/Users/someone/.cache/ytcast/ytcast.json",
                          "ytcast's own list sits in ~/.cache when XDG_CACHE_HOME is unset")
    }

    private static func commandLineImportRules(_ suite: TestSuite) {
        func importable(_ cli: Data?, _ app: Data?) -> [String] {
            TVCastSupport.importableIDs(fromCommandLine: cli, intoApp: app)
        }
        func imported(_ cli: Data?, _ app: Data?) -> Data? {
            TVCastSupport.importing(fromCommandLine: cli, intoApp: app)
        }
        let cli = data([entry("cli", used: true, name: "YouTube on TV")])
        let unusable: [(Data?, String)] = [
            (nil, "no command line list"), (Data(), "an empty file"), (Data("{oops".utf8), "a malformed list"),
            (Data("null".utf8), "ytcast's empty list"), (Data("{\"a\":1}".utf8), "a list of the wrong type"),
            (data([discovered("uuid:d", name: "Bedroom")]), "a list holding only a discovered TV"),
        ]
        for (source, label) in unusable {
            suite.expect(importable(source, nil).isEmpty && imported(source, nil) == nil,
                         "\(label) imports nothing")
        }
        for (app, label) in [(nil, "no list"), (Data(), "an empty file"), (Data("null".utf8), "null"),
                             (Data("[]".utf8), "an empty list")] as [(Data?, String)] {
            suite.expectEqual(importable(cli, app), ["cli"], "a code-paired TV is offered to \(label)")
            suite.expectEqual(ids(imported(cli, app)), ["cli"], "a code-paired TV is copied into \(label)")
            suite.expectEqual(lastUsed("cli", in: imported(cli, app)), true,
                              "with no TV of its own, the list takes ytcast's last used TV as is (\(label))")
        }
        suite.expect(importable(cli, cli).isEmpty && imported(cli, cli) == nil,
                     "a TV the list already has is not imported again")
        let elsewhere = data([entry("app", screen: "S1")])
        let sameScreen = data([entry("cli", screen: "S1")])
        suite.expect(importable(sameScreen, elsewhere).isEmpty && imported(sameScreen, elsewhere) == nil,
                     "a pairing of a screen the list already pairs with is the same TV, not a new one")
        for broken in [Data("oops".utf8), Data("{\"a\":1}".utf8)] {
            suite.expect(importable(cli, broken).isEmpty && imported(cli, broken) == nil,
                         "a list that cannot be read is never written over")
        }
        let twice = data([entry("dup", token: "first"), entry("dup", token: "second")])
        suite.expectEqual(importable(twice, nil), ["dup"], "an id listed twice is offered once")
        suite.expectEqual(ids(imported(twice, nil)), ["dup"], "an id listed twice is copied once")
        suite.expectEqual(remoteField("LoungeToken", of: "dup", in: imported(twice, nil)), "second",
                          "as in ytcast's own loading, the last entry with an id wins")
    }

    private static func commandLineMergeRules(_ suite: TestSuite) {
        let app = data([entry("app", used: true, name: "Den"), discovered("uuid:d", name: "Bedroom")])
        let cli = data([
            discovered("uuid:other", name: "Office"), entry("app", token: "cli-token"),
            entry("new1", used: true, name: "Kitchen"), entry("new2", name: "Attic"),
        ])
        suite.expectEqual(TVCastSupport.importableIDs(fromCommandLine: cli, intoApp: app), ["new1", "new2"],
                          "only code-paired TVs the list lacks are offered, in ytcast's order")
        let merged = TVCastSupport.importing(fromCommandLine: cli, intoApp: app)
        suite.expectEqual(ids(merged), ["app", "uuid:d", "new1", "new2"],
                          "the list keeps its TVs and gains the new ones after them")
        suite.expectEqual(remoteField("LoungeToken", of: "app", in: merged), "t",
                          "a TV the list already has keeps its own pairing")
        suite.expectEqual(lastUsed("app", in: merged), true, "the list's own last used TV stays last used")
        suite.expect(lastUsed("new1", in: merged) == false && lastUsed("new2", in: merged) == false,
                     "an imported TV is not last used in a list that has its own")
        suite.expectEqual(TVCastSupport.devices(fromCache: merged).filter(\.pairedWithCode).map(\.name),
                          ["Den", "Attic", "Kitchen"], "the merged list reads like any other")
        suite.expect(TVCastSupport.importableIDs(fromCommandLine: cli, intoApp: merged).isEmpty,
                     "once imported, nothing is left to offer")
    }

    private static func commandLineFidelityRules(_ suite: TestSuite) {
        let merged = TVCastSupport.importing(fromCommandLine: richCache, intoApp: data([entry("app")]))
        let entries = parse(merged)
        suite.expectEqual(ids(merged), ["app", "dev-code"], "the discovered TV in the same list stays behind")
        let copied = entries?.last
        let remote = copied?["Remote"] as? [String: Any]
        suite.expect(copied?["Device"] is NSNull, "Device stays null, so ytcast still reads it as paired with a code")
        suite.expectEqual(remote?["ScreenName"] as? String, "Living room", "the name is copied")
        suite.expectEqual(remote?["LoungeToken"] as? String, "tok", "the pairing token is copied")
        suite.expectEqual(remote?["SId"] as? String, "sid", "the session fields are copied")
        suite.expectEqual((remote?["Expiration"] as? NSNumber)?.int64Value, 1_790_000_000_123,
                          "Expiration stays exact")
        suite.expect((remote?["Expiration"] as? NSNumber).map { !CFNumberIsFloatType($0) } == true,
                     "Expiration stays an integer")
        suite.expectEqual((remote?["Future"] as? [Any])?.count, 2, "unknown Remote fields are copied")
        let extra = copied?["Extra"] as? [String: Any]
        suite.expectEqual((extra?["n"] as? NSNumber)?.int64Value, 10_000_000_000,
                          "unknown top-level fields are copied")
        suite.expectEqual(copied?["LastUsed"] as? Bool, false, "LastUsed is cleared beside the list's own TV")
        let text = merged.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        suite.expect(!text.contains("1.79") && !text.contains("e+"),
                     "integers are not serialized as floats: \(text.count) bytes")
        let alone = parse(TVCastSupport.importing(fromCommandLine: richCache, intoApp: nil))
        suite.expectEqual(alone?.first?["LastUsed"] as? Bool, true, "into an empty list LastUsed is kept")
    }

    // MARK: Failure

    private static func failureRules(_ suite: TestSuite) {
        func failure(_ output: String, _ status: Int32 = 1, timedOut: Bool = false) -> TVCastFailure? {
            TVCastSupport.failure(fromOutput: output, status: status, timedOut: timedOut)
        }
        suite.expectEqual(failure("anything", 1, timedOut: true), .timedOut, "a timeout wins")
        suite.expectEqual(failure("anything", 0, timedOut: true), .timedOut, "a timeout wins over status 0")
        suite.expect(failure("playing\n", 0) == nil, "success has no failure")
        suite.expectEqual(failure("ytcast: invalid pairing code\n"), .invalidCode, "invalid code")
        suite.expectEqual(failure("ytcast: no device matches \"x\"\n"), .deviceNotFound, "no match")
        suite.expectEqual(failure("ytcast: no device found\n"), .deviceNotFound, "no device")
        suite.expectEqual(failure("ytcast: ConnectWithCode: unexpected status 400"), .pairingRejected,
                          "pairing rejected")
        let wrongCode = "ytcast: ConnectWithCode: GET https://www.youtube.com/api/lounge/pairing/get_screen: "
            + "404 Not Found"
        suite.expectEqual(failure(wrongCode), .pairingRejected, "a real wrong code stays a rejected pairing")
        suite.expectEqual(failure(wrongCode + ": bad HTTP response status\n"), .pairingRejected,
                          "with ytcast's own suffix too")
        suite.expectEqual(failure("ytcast: Connect: unexpected status 400"), .unreachable, "reconnect failed")
        suite.expectEqual(failure("ytcast: x: RefreshToken: expired"), .unreachable, "token refresh failed")
        suite.expectEqual(failure("ytcast: Play: status 500"), .playbackRejected, "play rejected")
        suite.expectEqual(failure("ytcast: Add: status 500"), .playbackRejected, "add rejected")
        suite.expectEqual(failure("ytcast: something odd"), .failed("something odd"), "unknown message")
        suite.expectEqual(failure("2026/01/01 log line\nytcast: first\nnoise\nytcast: Play: last\ntrailing noise\n"),
                          .playbackRejected, "the last ytcast line is the verdict")
        suite.expectEqual(failure("panic: boom\n\n  \n"), .failed("panic: boom"), "no prefix falls back to last line")
        suite.expectEqual(failure("", 3), .exited(3), "empty output keeps the status, not a sentence")
        suite.expectEqual(failure("  \n\n", 2), .exited(2), "blank output keeps the status")
        suite.expectEqual(failure("", 9), .exited(9), "a signal number is kept as it came")
    }

    private static func networkFailureRules(_ suite: TestSuite) {
        func failure(_ message: String) -> TVCastFailure? {
            TVCastSupport.failure(fromOutput: "ytcast: " + message + "\n", status: 1, timedOut: false)
        }
        let url = "\"https://www.youtube.com/api/lounge/bc/bind?RID=1\""
        let timedOut = [
            "Play: getSessionIds: Post \(url): context deadline exceeded "
                + "(Client.Timeout exceeded while awaiting headers)",
            "ConnectWithCode: Get \(url): net/http: request canceled (Client.Timeout exceeded while awaiting headers)",
            "Connect: RefreshToken: Post \(url): CONTEXT DEADLINE EXCEEDED",
        ]
        for message in timedOut {
            suite.expectEqual(failure(message), .timedOut, "Go's own request timeout: \(message)")
        }
        let offline = [
            "ConnectWithCode: dial tcp: lookup www.youtube.com: no such host",
            "Connect: read tcp: network is unreachable",
            "Play: Post: i/o timeout",
            "Connect: CONNECTION REFUSED",
            "Add: net/http: TLS handshake timeout",
            "Play: connection reset by peer",
            "Connect: RefreshToken: Post \(url): dial tcp 142.250.1.1:443: connect: no route to host",
            "ConnectWithCode: Get \(url): dial tcp 142.250.1.1:443: connect: operation timed out",
            "Play: getSessionIds: Post \(url): dial tcp: connect: network is down",
            "ConnectWithCode: Get \(url): dial tcp: lookup www.youtube.com on 192.168.1.1:53: server misbehaving",
            "Play: Post \(url): remote error: tls: handshake failure",
            "Connect: RefreshToken: Post \(url): x509: certificate has expired or is not yet valid",
            "Play: getSessionIds: Post \(url): EOF",
            "EOF",
        ]
        for message in offline {
            suite.expectEqual(failure(message), .offline, "a network failure: \(message)")
        }
        suite.expectEqual(failure("Play: Post \(url): unexpected EOF"), .playbackRejected,
                          "only a bare EOF at the end is the connection dropping")
        suite.expectEqual(failure("Play: EOF while reading"), .playbackRejected, "EOF mid-message is not a needle")
    }

    // MARK: Service source

    /// The service is the one place ytcast runs, so what it may run is pinned
    /// here: any other mode, or a cast to a TV ytcast has not saved with a
    /// code, searches the local network, and docs/PRIVACY.md promises a
    /// code-paired TV is reached through YouTube alone.
    private static func serviceSourceRules(_ suite: TestSuite) {
        let source = (try? String(contentsOfFile: "Sources/Vorssaint/Services/TVCast/TVCastService.swift",
                                  encoding: .utf8)) ?? ""
        let code = source.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        suite.expect(!code.isEmpty, "the TV cast service source is readable")
        suite.expect(code.components(separatedBy: "BoundedProcessRunner.").count == 2
                && code.contains("BoundedProcessRunner.run(helper, command.arguments,"),
               "ytcast runs from exactly one call, with a Command's arguments")
        suite.expect(code.contains("TVCastSupport.pairArguments(code: code)")
                && code.contains("TVCastSupport.castArguments(deviceID: deviceID, video: video)")
                && code.components(separatedBy: "\"-").count == 1,
               "a Command builds only the pair and cast arguments, and no other flag is spelled out")
        sendGuardRules(suite, code: code)
        commandLineReadOnlyRules(suite, code: code)
        suite.expect(!code.contains("NSLog") && !code.contains("print(") && !code.contains("/tmp")
                && !code.contains("as!") && !code.contains("usleep"),
               "the TV cast service logs through Logger only and neither force-casts nor sleeps")
        suite.expect(code.contains("\"PATH\": \"/usr/bin:/bin\"") && code.contains("\"XDG_CACHE_HOME\": directory.path")
                && code.contains("BundledHelper.path(named: helperName)"),
               "ytcast runs the bundled copy with a fixed PATH and Vorssaint's own cache directory")
        // ytcast introduces itself to YouTube, and on the TV, as account@computer
        // when it can name the account. The release build looks the account up
        // only through these variables, so passing them, or the app's whole
        // environment, would send the Mac's account and computer name out.
        suite.expect(!source.contains("\"USER\"") && !source.contains("\"LOGNAME\"")
                && !code.contains("processInfo.environment"),
               "ytcast gets no USER or LOGNAME, so it stays a generic remote")
        suite.expect(code.contains("private static let stateDirectory = PrivateFileStore.containerURL?")
                && code.contains(".appendingPathComponent(\"TVCast\", isDirectory: true)")
                && code.contains("PrivateFileStore.write(") && code.contains("PrivateFileStore.createDirectory(")
                && !code.contains("applicationSupportDirectory") && !code.contains("posixPermissions"),
               "the TV list lives in this build's own container and is written through PrivateFileStore")
        suite.expect(code.contains("private static func run(_ command: Command, snapshot: Data?,")
                && code.contains("TVCastSupport.repairedCache(snapshot: snapshot,"),
               "every ytcast run is handed the cache as it was, to put back what ytcast loses")
    }

    private static func sendGuardRules(_ suite: TestSuite, code: String) {
        let send = code.components(separatedBy: "private static func performSend(").dropFirst().first?
            .components(separatedBy: "private static func run(").first ?? ""
        let guardsFirst: Bool = {
            guard let check = send.range(of: ".contains(where: { $0.id == id && $0.pairedWithCode })"),
                  let cast = send.range(of: "run(.cast(") else { return false }
            return check.upperBound <= cast.lowerBound
        }()
        suite.expect(send.contains("TVCastSupport.devices(fromCache: snapshot)")
                && send.contains(".failed(.deviceNotFound, during: .send)")
                && guardsFirst,
               "a cast runs only after the TV is found in the cache file, paired with a code")
        suite.expect(code.contains("TVCastSupport.devices(fromCache: readCache()).filter(\\.pairedWithCode)"),
               "the service lists only TVs paired with a code")
    }

    /// The command line's ytcast owns its list, and docs/PRIVACY.md promises
    /// Vorssaint never changes it: one read touches it, and every write goes
    /// to Vorssaint's own list or its import marker.
    private static func commandLineReadOnlyRules(_ suite: TestSuite, code: String) {
        suite.expect(code.contains("private static let commandLineCacheURL = TVCastSupport.commandLineCacheURL(")
                && code.contains("home: FileManager.default.homeDirectoryForCurrentUser)")
                && code.contains("let url = commandLineCacheURL.resolvingSymlinksInPath()")
                && code.components(separatedBy: "commandLineCacheURL").count == 4,
               "ytcast's own list is found from the home folder and used by one read only")
        let writes = code.components(separatedBy: "PrivateFileStore.write(").dropFirst()
        let ownFiles = ["data, to: cacheURL)", "Data(), to: marker)"]
        suite.expect(writes.count == 2 && writes.allSatisfy { write in ownFiles.contains(where: write.hasPrefix) },
               "the service writes only its own list and its import marker")
        let fileChanges = [".write(to:", "removeItem", "moveItem", "replaceItem", "copyItem", "linkItem",
                           "createFile", "forWritingTo", "forUpdating", "trashItem", "setAttributes",
                           "createSymbolicLink"]
        suite.expect(!fileChanges.contains(where: code.contains),
               "nothing else in the service writes, moves or deletes a file")
        let importer = code.components(separatedBy: "private static func importCommandLineTVs()").dropFirst().first?
            .components(separatedBy: "private static func listing()").first ?? ""
        suite.expect(code.contains("edit { Self.importCommandLineTVs()")
                && importer.contains("writeCache(merged)") && !importer.contains("run("),
               "an import is an edit of the list and runs no ytcast")
    }
}

private extension TestSuite {
    func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        expect(actual == expected, "\(label): got \(actual), expected \(expected)", file: file, line: line)
    }
}
