// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The video on the TV, as of the last report, with the clock running
/// between reports while it plays.
struct TVCastPlayer: Equatable {
    enum Phase: Equatable {
        case playing
        /// Loading, or an ad: the video is under way but its clock stands.
        case buffering
        case paused
        /// Ended or not started.
        case stopped
    }

    let videoID: String
    let position: TimeInterval
    let duration: TimeInterval
    let phase: Phase
    let sampledAt: Date

    static func phase(for state: Int) -> Phase {
        switch state {
        case 1: return .playing
        case 3, 1081, 1082: return .buffering
        case 2, 5: return .paused
        default: return .stopped
        }
    }

    /// What pressing play or pause should ask for: pause while the video is
    /// under way, play otherwise.
    var isUnderWay: Bool { phase == .playing || phase == .buffering }

    func position(at date: Date) -> TimeInterval {
        guard phase == .playing else { return position }
        let advanced = position + max(0, date.timeIntervalSince(sampledAt))
        return duration > 0 ? min(duration, advanced) : advanced
    }

    func with(phase: Phase, at date: Date) -> TVCastPlayer {
        TVCastPlayer(videoID: videoID, position: position(at: date), duration: duration, phase: phase, sampledAt: date)
    }
}

/// The TV's session as the island shows it: how the link stands and what
/// plays. Events change it in order; nothing else reads YouTube's.
struct TVCastLiveState: Equatable {
    enum Link: Equatable {
        case connecting
        case connected
        /// The session holds, but YouTube is not open on the TV.
        case away
        case failed(TVCastFailure)
    }

    var link: Link = .connecting
    var player: TVCastPlayer?

    /// True when the event asks for the video it does not name: a state
    /// change while nothing was known to play.
    @discardableResult
    mutating func apply(_ event: TVCastLoungeEvent, at date: Date) -> Bool {
        switch event {
        case .nowPlaying(let report):
            link = .connected
            player = report.flatMap { report in
                guard let id = report.videoID, TVCastSupport.isVideoID(id) else { return nil }
                return TVCastPlayer(videoID: id, position: report.position, duration: report.duration,
                                    phase: TVCastPlayer.phase(for: report.state), sampledAt: date)
            }
        case .stateChanged(let report):
            link = .connected
            guard let current = player else { return TVCastPlayer.phase(for: report.state) != .stopped }
            player = TVCastPlayer(videoID: current.videoID, position: report.position,
                                  duration: report.duration > 0 ? report.duration : current.duration,
                                  phase: TVCastPlayer.phase(for: report.state), sampledAt: date)
        case .loungeStatus(let present):
            guard let present else { break }
            link = present ? .connected : .away
            if !present { player = nil }
        case .screenDisconnected:
            link = .away
            player = nil
        case .sessionID, .gsessionID, .other:
            break
        }
        return false
    }

    /// What YouTube took a control as doing, until the TV reports it.
    mutating func expect(_ playback: TVCastPlayback, at date: Date) {
        switch playback {
        case .play: player = player?.with(phase: .playing, at: date)
        case .pause: player = player?.with(phase: .paused, at: date)
        case .stop: player = nil
        }
    }
}

/// A video's title and channel, as YouTube's oEmbed gives them to anyone.
struct TVCastVideoDetails: Equatable {
    let title: String
    let channel: String
}

/// The requests for what the Lounge API leaves out: a title and a picture.
/// Both are public, need no account and carry nothing but the video's id.
enum TVCastVideoLookup {
    /// Nil for anything that is not a video id, which never reaches a URL.
    static func detailsRequest(videoID: String) -> URLRequest? {
        guard TVCastSupport.isVideoID(videoID) else { return nil }
        var components = URLComponents(string: "https://www.youtube.com/oembed")
        components?.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=" + videoID),
        ]
        return components?.url.map { URLRequest(url: $0) }
    }

    static func details(status: Int, body: Data) -> TVCastVideoDetails? {
        guard status == 200,
              let reply = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let title = (reply["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        let channel = (reply["author_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return TVCastVideoDetails(title: title, channel: channel)
    }

    /// The 320 by 180 frame, 16:9 without the bars the larger ones carry.
    static func thumbnailRequest(videoID: String) -> URLRequest? {
        guard TVCastSupport.isVideoID(videoID),
              let url = URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg") else { return nil }
        return URLRequest(url: url)
    }
}
