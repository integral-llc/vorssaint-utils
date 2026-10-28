// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The playback controls and the island's player speak YouTube's Lounge API
/// themselves, in ytcast v1.4.1's own requests and pyytlounge's for what
/// ytcast never sends, and only read the TV list.
enum TVCastLoungeTests {
    static func run(_ suite: TestSuite) {
        commandRules(suite)
        screenRules(suite)
        expiryRules(suite)
        bindRequestRules(suite)
        commandRequestRules(suite)
        subscribeRequestRules(suite)
        renewalRules(suite)
        sessionRules(suite)
        frameRules(suite)
        eventRules(suite)
        liveStateRules(suite)
        clockRules(suite)
        lookupRules(suite)
        displayLinkRules(suite)
        failureRules(suite)
        stringRules(suite)
        sourceRules(suite)
    }

    private static func query(_ request: URLRequest) -> [String: String] {
        let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    private static func body(_ request: URLRequest) -> String {
        request.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    private static func cache(_ remote: String, device: String = "null") -> Data {
        Data("[{\"Device\": \(device), \"Remote\": \(remote), \"LastUsed\": true}]".utf8)
    }

    private static let session = TVCastLoungeSession(sid: "sid-1", gsessionID: "gs-1")

    private static func commandRules(_ suite: TestSuite) {
        suite.expect(TVCastPlayback.allCases.map(\.command) == ["play", "pause", "stopVideo"],
                     "the controls send YouTube's own play, pause and stopVideo")
        suite.expect(TVCastPlayback.allCases.map(\.symbol) == ["play.fill", "pause.fill", "stop.fill"],
                     "each control wears its transport glyph")
    }

    private static func screenRules(_ suite: TestSuite) {
        let paired = cache("{\"ScreenId\": \"scr\", \"DeviceId\": \"dev\", \"LoungeToken\": \"tok\", "
            + "\"Expiration\": 1767225600000, \"ScreenName\": \"Living room\"}")
        suite.expect(TVCastSupport.loungeScreen(for: "dev", inCache: paired)
                     == TVCastLoungeScreen(screenID: "scr", loungeToken: "tok", expiration: 1_767_225_600_000),
                     "a TV paired with a code gives its screen, token and expiry")
        suite.expect(TVCastSupport.loungeScreen(for: "other", inCache: paired) == nil,
                     "a TV the list lacks has no screen")
        let discovered = cache("{\"ScreenId\": \"scr\", \"LoungeToken\": \"tok\"}",
                               device: "{\"UniqueServiceName\": \"dev\", \"FriendlyName\": \"TV\"}")
        suite.expect(TVCastSupport.loungeScreen(for: "dev", inCache: discovered) == nil,
                     "a discovered TV is never controlled, as it is never cast to")
        let tokenless = cache("{\"ScreenId\": \"scr\", \"DeviceId\": \"dev\", \"LoungeToken\": \"\"}")
        suite.expect(TVCastSupport.loungeScreen(for: "dev", inCache: tokenless) == nil,
                     "a pairing without a token has nothing to send with")
        let timeless = cache("{\"ScreenId\": \"scr\", \"DeviceId\": \"dev\", \"LoungeToken\": \"tok\"}")
        suite.expect(TVCastSupport.loungeScreen(for: "dev", inCache: timeless)?.expiration == 0,
                     "a pairing without an expiry counts as lapsed, so the token is renewed first")
        suite.expect(TVCastSupport.loungeScreen(for: "dev", inCache: nil) == nil
                     && TVCastSupport.loungeScreen(for: "dev", inCache: Data("null".utf8)) == nil,
                     "no list, or ytcast's empty one, has no screen")
    }

    private static func expiryRules(_ suite: TestSuite) {
        let screen = TVCastLoungeScreen(screenID: "s", loungeToken: "t", expiration: 2_000_000)
        suite.expect(!screen.isExpired(at: Date(timeIntervalSince1970: 1_999))
                     && !screen.isExpired(at: Date(timeIntervalSince1970: 2_000))
                     && screen.isExpired(at: Date(timeIntervalSince1970: 2_000.001)),
                     "a token lapses past its expiry in milliseconds, not at it, as ytcast's Expired")
    }

    private static func bindRequestRules(_ suite: TestSuite) {
        let request = TVCastLounge.bindRequest(token: "tok")
        suite.expect(request.httpMethod == "POST"
                     && request.url?.absoluteString.hasPrefix("https://www.youtube.com/api/lounge/bc/bind?") == true
                     && request.httpBody == nil
                     && request.value(forHTTPHeaderField: "Content-Type") == nil,
                     "joining the session is ytcast's empty POST to bind")
        suite.expect(query(request) == ["CVER": "1", "RID": "1", "VER": "8", "app": "youtube-desktop",
                                        "device": "REMOTE_CONTROL", "id": "remote", "loungeIdToken": "tok",
                                        "name": "ytcast"],
                     "the bind names the remote as ytcast does, so the TV sees one remote: \(query(request))")
        suite.expect(request.value(forHTTPHeaderField: "Origin") == "https://www.youtube.com"
                     && request.value(forHTTPHeaderField: "User-Agent")?.contains("Chrome/96.0.4664.45") == true,
                     "every request carries ytcast's Origin and browser user agent")
        let escaped = TVCastLounge.bindRequest(token: "a+b/c=d e")
        let encoded = escaped.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.percentEncodedQuery
        suite.expect(encoded?.contains("loungeIdToken=a%2Bb%2Fc%3Dd%20e") == true
                     && query(escaped)["loungeIdToken"] == "a+b/c=d e",
                     "a token's + and / reach YouTube escaped, never as a space or a path")
    }

    private static func commandRequestRules(_ suite: TestSuite) {
        for playback in TVCastPlayback.allCases {
            let request = TVCastLounge.commandRequest(playback.command, token: "tok", session: session, number: 1)
            suite.expect(request.httpMethod == "POST"
                         && request.url?.path == "/api/lounge/bc/bind"
                         && query(request) == ["CVER": "1", "RID": "2", "SID": "sid-1", "VER": "8",
                                               "gsessionid": "gs-1", "loungeIdToken": "tok"]
                         && body(request) == "count=1&ofs=1&req0__sc=\(playback.command)"
                         && request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded",
                         "\(playback.command) goes in the shape of ytcast's Play, first after the bind")
        }
        let third = TVCastLounge.commandRequest(TVCastLounge.nowPlayingCommand, token: "tok", session: session, number: 3)
        suite.expect(query(third)["RID"] == "4" && body(third) == "count=1&ofs=3&req0__sc=getNowPlaying",
                     "later commands on one session count on, as pyytlounge numbers them")
        suite.expect(TVCastLounge.sessionLost(status: 400) && TVCastLounge.sessionLost(status: 404)
                     && TVCastLounge.sessionLost(status: 410)
                     && !TVCastLounge.sessionLost(status: 401) && !TVCastLounge.sessionLost(status: 200),
                     "an unknown or gone session is joined again; a turned-down token is renewed instead")
    }

    private static func subscribeRequestRules(_ suite: TestSuite) {
        let request = TVCastLounge.subscribeRequest(token: "a+b", session: session, lastEventID: 7)
        suite.expect(request.httpMethod == "GET" && request.httpBody == nil
                     && request.url?.path == "/api/lounge/bc/bind"
                     && query(request) == ["name": "ytcast", "loungeIdToken": "a+b", "SID": "sid-1", "AID": "7",
                                           "gsessionid": "gs-1", "device": "REMOTE_CONTROL", "app": "youtube-desktop",
                                           "VER": "8", "v": "2", "RID": "rpc", "CI": "0", "TYPE": "xmlhttp"],
                     "the stream asks for the session's events past the last one read, as pyytlounge subscribes")
        suite.expect(request.value(forHTTPHeaderField: "Origin") == "https://www.youtube.com"
                     && request.value(forHTTPHeaderField: "User-Agent")?.contains("Chrome/96.0.4664.45") == true,
                     "the stream comes from the same remote as every other request")
    }

    private static func renewalRules(_ suite: TestSuite) {
        let request = TVCastLounge.renewalRequest(screenID: "scr/1")
        suite.expect(request.httpMethod == "POST"
                     && request.url?.absoluteString == "https://www.youtube.com/api/lounge/pairing/get_lounge_token_batch"
                     && body(request) == "screen_ids=scr%2F1",
                     "a lapsed token is renewed for the TV's screen, as ytcast's RefreshToken")
        let reply = Data("{\"screens\": [{\"screenId\": \"scr\", \"loungeToken\": \"fresh\", \"expiration\": 1}]}".utf8)
        suite.expect(TVCastLounge.renewedToken(status: 200, body: reply) == "fresh",
                     "the renewed token is the first screen's")
        suite.expect(TVCastLounge.renewedToken(status: 500, body: reply) == nil
                     && TVCastLounge.renewedToken(status: 200, body: Data("{\"screens\": []}".utf8)) == nil
                     && TVCastLounge.renewedToken(status: 200, body: Data("{\"screens\": [{\"loungeToken\": \"\"}]}".utf8)) == nil
                     && TVCastLounge.renewedToken(status: 200, body: Data("<html>".utf8)) == nil,
                     "an error, no screen, an empty token or no JSON renews nothing")
        suite.expect(TVCastLounge.tokenRejected(status: 401) && !TVCastLounge.tokenRejected(status: 400)
                     && !TVCastLounge.tokenRejected(status: 200),
                     "only YouTube's 401 calls for one renewal")
    }

    private static func sessionRules(_ suite: TestSuite) {
        // ytcast's own TestExtractSessionIds reply.
        let reply = Data("""

            270
            [[0,["c","sid-foo-bar-baz","",8]]
            ,[1,["S","gsessionid-foo-bar-baz"]]
            ,[2,["loungeStatus",{}]]
            ,[3,["playlistModified",{}]]
            ,[4,["onAutoplayModeChanged",{"autoplayMode":"UNSUPPORTED"}]]
            ,[5,["onPlaylistModeChanged",{"shuffleEnabled":"false","loopEnabled":"false"}]]
            ]
            """.utf8)
        suite.expect(TVCastLounge.session(status: 200, body: reply)
                     == TVCastLoungeSession(sid: "sid-foo-bar-baz", gsessionID: "gsessionid-foo-bar-baz"),
                     "the session ids come out of the bind's events past its length")
        suite.expect(TVCastLounge.messages(inReply: reply).map(\.id) == [0, 1, 2, 3, 4, 5],
                     "every event of the bind is read, so the stream starts after the last")
        let noGsession = Data("10\n[[0,[\"c\",\"sid\",\"\",8]]]".utf8)
        suite.expect(TVCastLounge.session(status: 200, body: noGsession) == nil
                     && TVCastLounge.session(status: 400, body: reply) == nil
                     && TVCastLounge.session(status: 200, body: Data("no events".utf8)) == nil
                     && TVCastLounge.session(status: 200, body: Data("[[0,[\"c\",7]],[1]]".utf8)) == nil,
                     "a reply without both ids, an error status or no events joins nothing")
    }

    private static func frames(_ chunks: [String]) -> (frames: [String], overflowed: Bool) {
        var splitter = TVCastLoungeFrames()
        let found = chunks.flatMap { splitter.append(Data($0.utf8)) }.map { String(decoding: $0, as: UTF8.self) }
        return (found, splitter.overflowed)
    }

    private static func frameRules(_ suite: TestSuite) {
        let one = #"[[1,["noop"]]]"#
        suite.expect(frames(["14\n" + one]).frames == [one],
                     "a frame is the array after its length")
        suite.expect(frames(["14\n[[1,[\"no", "op\"]]]\n", "14\n" + one]).frames == [one, one],
                     "a frame split across reads comes out whole, and the next one after it")
        let tricky = #"[[2,["x",{"a":"] [ \" ]","b":"Salón"}]]]"#
        suite.expect(frames(["40\n" + tricky + "\n14\n" + one]).frames == [tricky, one],
                     "brackets and escaped quotes inside strings, and non-ASCII names, do not end a frame")
        let open = "9\n[[1,[\"" + String(repeating: "x", count: TVCastLoungeFrames.maxPending)
        let overflow = frames([open, "\"]]]"])
        suite.expect(overflow.overflowed && overflow.frames.isEmpty,
                     "a frame that never closes is dropped once it runs past any the API sends")
    }

    private static func eventRules(_ suite: TestSuite) {
        let frame = Data(#"""
            [[3,["nowPlaying",{"videoId":"jfKfPfyJRdk","currentTime":"101.5","duration":"213","state":"1"}]]
            ,[4,["onStateChange",{"currentTime":"102","duration":"213","state":"2"}]]
            ,[5,["nowPlaying",{}]]
            ,[6,["loungeStatus",{"devices":"[{\"type\":\"LOUNGE_SCREEN\",\"name\":\"TV\"}]"}]]
            ,[7,["loungeStatus",{"devices":"[{\"type\":\"REMOTE_CONTROL\"}]"}]]
            ,[8,["loungeStatus",{}]]
            ,[9,["loungeScreenDisconnected",{}]]
            ,[10,["onVolumeChanged",{"volume":"20"}]]
            ,"garbage",[11]
            ]
            """#.utf8)
        let messages = TVCastLounge.messages(in: frame)
        suite.expect(messages.map(\.id) == [3, 4, 5, 6, 7, 8, 9, 10],
                     "each event keeps its id, and an entry of another shape is skipped: \(messages.map(\.id))")
        suite.expect(messages.map(\.event) == [
            .nowPlaying(TVCastPlayerReport(videoID: "jfKfPfyJRdk", position: 101.5, duration: 213, state: 1)),
            .stateChanged(TVCastPlayerReport(videoID: nil, position: 102, duration: 213, state: 2)),
            .nowPlaying(nil),
            .loungeStatus(screenPresent: true),
            .loungeStatus(screenPresent: false),
            .loungeStatus(screenPresent: nil),
            .screenDisconnected,
            .other,
        ], "YouTube's string numbers, an empty nowPlaying and who the session lists all read as the TV meant")
        suite.expect(TVCastLounge.messages(in: Data("not json".utf8)).isEmpty
                     && TVCastLounge.messages(in: Data(#"{"a":1}"#.utf8)).isEmpty,
                     "a frame that is not a list of events holds none")
    }

    private static func report(_ state: Int, at position: TimeInterval = 10,
                               video: String? = "jfKfPfyJRdk") -> TVCastPlayerReport {
        TVCastPlayerReport(videoID: video, position: position, duration: 200, state: state)
    }

    private static func liveStateRules(_ suite: TestSuite) {
        let start = Date(timeIntervalSince1970: 1_000)
        var state = TVCastLiveState()
        suite.expect(state.link == .connecting && state.player == nil, "a new look starts out connecting")
        suite.expect(!state.apply(.nowPlaying(report(1)), at: start)
                     && state.link == .connected && state.player?.videoID == "jfKfPfyJRdk"
                     && state.player?.phase == .playing,
                     "what the TV plays connects the page and names the video")
        state.apply(.stateChanged(report(2, at: 30, video: nil)), at: start.addingTimeInterval(5))
        suite.expect(state.player?.videoID == "jfKfPfyJRdk" && state.player?.phase == .paused
                     && state.player?.position == 30,
                     "a state change keeps the video and takes the TV's clock")
        state.expect(.play, at: start.addingTimeInterval(6))
        suite.expect(state.player?.phase == .playing && state.player?.position == 30,
                     "a play YouTube took shows at once, from where the clock stood")
        state.expect(.pause, at: start.addingTimeInterval(8))
        suite.expect(state.player?.phase == .paused && state.player?.position == 32,
                     "a pause stops the clock where it ran to")
        state.expect(.stop, at: start.addingTimeInterval(9))
        suite.expect(state.player == nil, "a stop clears the player")
        suite.expect(state.apply(.stateChanged(report(1, video: nil)), at: start) && state.player == nil,
                     "a state change with no known video asks what plays")
        suite.expect(!state.apply(.stateChanged(report(0, video: nil)), at: start),
                     "an ended video with none known asks nothing")
        state.apply(.nowPlaying(report(1, video: "not an id")), at: start)
        suite.expect(state.player == nil, "a video id of the wrong shape is never shown or looked up")
        state.apply(.nowPlaying(report(1)), at: start)
        state.apply(.loungeStatus(screenPresent: nil), at: start)
        suite.expect(state.link == .connected && state.player != nil, "a status that lists no one changes nothing")
        state.apply(.loungeStatus(screenPresent: false), at: start)
        suite.expect(state.link == .away && state.player == nil, "a session without the TV is away and plays nothing")
        state.apply(.loungeStatus(screenPresent: true), at: start)
        state.apply(.nowPlaying(report(2)), at: start)
        state.apply(.screenDisconnected, at: start)
        suite.expect(state.link == .away && state.player == nil, "the TV leaving takes its video with it")
        suite.expect([1, 3, 1081, 1082, 2, 5, 0, -1, 99].map(TVCastPlayer.phase(for:))
                     == [.playing, .buffering, .buffering, .buffering, .paused, .paused, .stopped, .stopped, .stopped],
                     "YouTube's player states, ads included, map to what the controls need")
        let buffering = TVCastPlayer(videoID: "v", position: 0, duration: 0, phase: .buffering, sampledAt: start)
        suite.expect(buffering.isUnderWay && !buffering.with(phase: .paused, at: start).isUnderWay,
                     "a loading video offers pause, as one playing does")
    }

    private static func clockRules(_ suite: TestSuite) {
        let start = Date(timeIntervalSince1970: 1_000)
        let playing = TVCastPlayer(videoID: "v", position: 100, duration: 120, phase: .playing, sampledAt: start)
        suite.expect(playing.position(at: start.addingTimeInterval(5)) == 105
                     && playing.position(at: start.addingTimeInterval(60)) == 120
                     && playing.position(at: start.addingTimeInterval(-5)) == 100,
                     "the clock runs between reports, stops at the end and never runs back")
        let live = TVCastPlayer(videoID: "v", position: 100, duration: 0, phase: .playing, sampledAt: start)
        suite.expect(live.position(at: start.addingTimeInterval(5)) == 105, "a stream with no length keeps running")
        let paused = TVCastPlayer(videoID: "v", position: 100, duration: 120, phase: .paused, sampledAt: start)
        suite.expect(paused.position(at: start.addingTimeInterval(5)) == 100, "a paused clock stands")
    }

    private static func lookupRules(_ suite: TestSuite) {
        let request = TVCastVideoLookup.detailsRequest(videoID: "jfKfPfyJRdk")
        let items = request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        suite.expect(request?.httpMethod == "GET" && items?.host == "www.youtube.com" && items?.path == "/oembed"
                     && items?.queryItems?.first { $0.name == "url" }?.value == "https://www.youtube.com/watch?v=jfKfPfyJRdk"
                     && items?.queryItems?.first { $0.name == "format" }?.value == "json"
                     && request?.value(forHTTPHeaderField: "Cookie") == nil,
                     "a title comes from YouTube's public oEmbed, asked with the video's id alone")
        suite.expect(TVCastVideoLookup.thumbnailRequest(videoID: "jfKfPfyJRdk")?.url?.absoluteString
                     == "https://i.ytimg.com/vi/jfKfPfyJRdk/mqdefault.jpg",
                     "the picture is YouTube's 16:9 thumbnail")
        suite.expect(["", "../../etc/x", "jfKfPfyJRd", "jfKfPfyJRdk?x", "a/b/c/d/e/f"].allSatisfy {
            TVCastVideoLookup.detailsRequest(videoID: $0) == nil && TVCastVideoLookup.thumbnailRequest(videoID: $0) == nil
        }, "nothing but an 11-character video id reaches a URL")
        let reply = Data(#"{"title":" lofi hip hop radio ","author_name":"Lofi Girl","type":"video"}"#.utf8)
        suite.expect(TVCastVideoLookup.details(status: 200, body: reply)
                     == TVCastVideoDetails(title: "lofi hip hop radio", channel: "Lofi Girl"),
                     "the title and channel come out of the reply, trimmed")
        suite.expect(TVCastVideoLookup.details(status: 200, body: Data(#"{"title":"t"}"#.utf8))
                     == TVCastVideoDetails(title: "t", channel: ""),
                     "a reply without a channel still names the video")
        suite.expect(TVCastVideoLookup.details(status: 401, body: reply) == nil
                     && TVCastVideoLookup.details(status: 200, body: Data(#"{"title":"  "}"#.utf8)) == nil
                     && TVCastVideoLookup.details(status: 200, body: Data("Unauthorized".utf8)) == nil,
                     "a private video, an empty title or no JSON names nothing")
    }

    private static func displayLinkRules(_ suite: TestSuite) {
        suite.expect(TVCastSupport.displayLink(for: "https://www.youtube.com/watch?v=jfKfPfyJRdk&si=abc")
                     == "youtube.com/watch?v=jfKfPfyJRdk"
                     && TVCastSupport.displayLink(for: " https://youtu.be/jfKfPfyJRdk?t=90 ")
                     == "youtube.com/watch?v=jfKfPfyJRdk&t=90",
                     "Play Copied Link shows the watch address it sends, without a scheme or tracking")
        suite.expect(TVCastSupport.displayLink(for: "https://example.com/watch?v=jfKfPfyJRdk") == nil
                     && TVCastSupport.displayLink(for: "") == nil,
                     "anything it would not send it does not show")
    }

    private static func failureRules(_ suite: TestSuite) {
        suite.expect(TVCastLounge.failure(for: .timedOut) == .timedOut
                     && TVCastLounge.failure(for: .notConnectedToInternet) == .offline
                     && TVCastLounge.failure(for: .cannotFindHost) == .offline
                     && TVCastLounge.failure(for: .secureConnectionFailed) == .offline,
                     "a request that never got an answer is a timeout or no connection")
    }

    private static func stringRules(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let text = FeatureStrings.tvCast(language)
            let titles = TVCastPlayback.allCases.map(text.title(for:))
            suite.expect(Set(titles).count == 3 && titles.allSatisfy { !$0.isEmpty } && !text.playbackLabel.isEmpty,
                         "each control has its own name, under a named row (\(language.rawValue))")
            suite.expect([text.pausedFormat, text.stoppedFormat].allSatisfy { $0.components(separatedBy: "%@").count == 2 }
                         && text.controlledMessage(.pause, on: "TV") != text.controlledMessage(.stop, on: "TV")
                         && text.controlledMessage(.play, on: "TV") == String(format: text.sentFormat, "TV"),
                         "pause and stop each name the TV once, and play says what a send says (\(language.rawValue))")
            let link = [text.connectedStatus, text.connectingStatus, text.offlineStatus]
            suite.expect(Set(link).count == 3 && link.allSatisfy { !$0.isEmpty && !$0.contains("%") }
                         && text.connectingStatus.hasSuffix("\u{2026}")
                         && !text.nowPlayingCaption.isEmpty && !text.nothingPlaying.isEmpty
                         && text.nothingPlaying != text.connectingStatus,
                         "each state of the link reads differently, and connecting goes on (\(language.rawValue))")
        }
    }

    private static func source(_ path: String) -> String {
        let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        return source.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// The controls only read the list, and reach YouTube through the
    /// requests checked above and nothing else.
    private static func sourceRules(_ suite: TestSuite) {
        let service = source("Sources/Vorssaint/Services/TVCast/TVCastService.swift")
        let control = service.components(separatedBy: "private static func performControl(").dropFirst().first?
            .components(separatedBy: "static func loungeScreen(").first ?? ""
        let guardsFirst: Bool = {
            guard let check = control.range(of: "loungeScreen(for: id)"),
                  let send = control.range(of: "TVCastLoungeChannel.shared.perform(") else { return false }
            return check.upperBound <= send.lowerBound
        }()
        suite.expect(guardsFirst && control.contains(".failed(.deviceNotFound, during: .control)")
                     && !control.contains("writeCache") && !control.contains("run("),
                     "a control finds the TV paired with a code first, runs no ytcast and writes no list")
        suite.expect(service.contains("TVCastLoungeChannel.shared.stop()"),
                     "switching the feature off ends the TV's session")
        let send = service.components(separatedBy: "private static func performSend(").dropFirst().first?
            .components(separatedBy: "private static func performControl(").first ?? ""
        let rejoinsAfterCast: Bool = {
            guard let cast = send.range(of: "run(.cast("),
                  let rejoin = send.range(of: "TVCastLoungeChannel.shared.rejoin("),
                  let failed = send.range(of: ".failed(failure, during: .send)") else { return false }
            return cast.upperBound <= rejoin.lowerBound && rejoin.upperBound <= failed.lowerBound
        }()
        suite.expect(rejoinsAfterCast,
                     "ytcast joins as the same remote, so after every cast, sent or not, the session joins again")
        let channel = source("Sources/Vorssaint/Services/TVCast/TVCastLoungeChannel.swift")
        let configured = { (needle: String) in channel.components(separatedBy: needle).count == 3 }
        suite.expect(!channel.isEmpty && !channel.contains("URLRequest(") && !channel.contains("URL(")
                     && !channel.contains("PrivateFileStore") && !channel.contains("write(")
                     && configured("URLSessionConfiguration.ephemeral")
                     && configured("configuration.httpCookieStorage = nil")
                     && configured("completionHandler(nil)"),
                     "the session builds no request of its own, writes nothing, and keeps no cookies or redirects")
        let lookup = source("Sources/Vorssaint/Services/TVCast/TVCastNowPlayingService.swift")
        suite.expect(!lookup.isEmpty && !lookup.contains("URLRequest(") && !lookup.contains("URL(")
                     && !lookup.contains("write(")
                     && lookup.contains("URLSessionConfiguration.ephemeral")
                     && lookup.contains("configuration.httpCookieStorage = nil")
                     && lookup.contains("configuration.urlCache = nil"),
                     "titles and pictures are asked without cookies, kept in memory and never written")
    }
}
