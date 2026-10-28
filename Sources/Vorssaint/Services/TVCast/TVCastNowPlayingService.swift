// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

/// What the TV in view plays, for the island's Cast page: the session's live
/// state for that TV, and the title, channel and picture YouTube gives for
/// its video. A TV is followed only while a page asks for it.
final class TVCastNowPlayingService: ObservableObject {
    static let shared = TVCastNowPlayingService()

    @Published private(set) var state = TVCastLiveState()
    /// For the video in `state`; nil until YouTube answers, and when it
    /// gives nothing, as for a private video.
    @Published private(set) var details: TVCastVideoDetails?
    @Published private(set) var thumbnail: NSImage?
    /// While YouTube is asked for the video in `state`.
    @Published private(set) var lookingUp = false

    private struct Lookup {
        let videoID: String
        let details: TVCastVideoDetails?
        let thumbnail: NSImage?
    }

    private static let timeout: TimeInterval = 15
    private static let maxDetailsBytes = 64 * 1024
    private static let maxThumbnailBytes = 1 << 20
    /// A few videos back, so returning to one shows it at once.
    private static let rememberedVideos = 8

    /// The TV a page asked for, set at once so an answer for one asked
    /// earlier is dropped.
    private var deviceID: String?
    private var screenID: String?
    private var videoID: String?
    private var lookups: [Lookup] = []
    private var pending: [URLSessionTask] = []
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    private init() {
        TVCastLoungeChannel.shared.onChange = { [weak self] screenID, state in
            self?.receive(state, for: screenID)
        }
    }

    /// Follows the TV with this id, or stops following with nil. On the
    /// main queue; the list is read off it.
    func watch(_ deviceID: String?) {
        let deviceID = AppFeature.tvCast.isAvailable ? deviceID : nil
        guard deviceID != self.deviceID else { return }
        self.deviceID = deviceID
        guard let deviceID else {
            TVCastLoungeChannel.shared.unwatch()
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let screen = TVCastService.loungeScreen(for: deviceID)
            DispatchQueue.main.async {
                guard let self, self.deviceID == deviceID else { return }
                guard let screen else {
                    TVCastLoungeChannel.shared.unwatch()
                    return
                }
                if self.screenID != screen.screenID {
                    self.screenID = screen.screenID
                    self.state = TVCastLiveState()
                    self.show(nil)
                }
                TVCastLoungeChannel.shared.watch(screen)
            }
        }
    }

    private func receive(_ state: TVCastLiveState, for screenID: String) {
        guard screenID == self.screenID else { return }
        if self.state != state { self.state = state }
        show(state.player?.videoID)
    }

    private func show(_ videoID: String?) {
        guard videoID != self.videoID else { return }
        self.videoID = videoID
        pending.forEach { $0.cancel() }
        pending = []
        lookingUp = false
        guard let videoID else {
            details = nil
            thumbnail = nil
            return
        }
        if let known = lookups.first(where: { $0.videoID == videoID }) {
            details = known.details
            thumbnail = known.thumbnail
            return
        }
        details = nil
        thumbnail = nil
        lookingUp = true
        lookUp(videoID)
    }

    /// Both answers are awaited and shown together. Only a lookup that got
    /// both is remembered: a failed one is tried again when the video comes
    /// back, and one cut short by the next video is dropped.
    private func lookUp(_ videoID: String) {
        let group = DispatchGroup()
        var details: TVCastVideoDetails?
        var thumbnail: NSImage?
        if let request = TVCastVideoLookup.detailsRequest(videoID: videoID) {
            group.enter()
            fetch(request, limit: Self.maxDetailsBytes) { status, body in
                details = TVCastVideoLookup.details(status: status, body: body)
                group.leave()
            }
        }
        if let request = TVCastVideoLookup.thumbnailRequest(videoID: videoID) {
            group.enter()
            fetch(request, limit: Self.maxThumbnailBytes) { status, body in
                thumbnail = status == 200 ? NSImage(data: body) : nil
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self, self.videoID == videoID else { return }
            self.pending = []
            self.lookingUp = false
            self.details = details
            self.thumbnail = thumbnail
            guard details != nil, thumbnail != nil else { return }
            self.lookups = [Lookup(videoID: videoID, details: details, thumbnail: thumbnail)]
                + self.lookups.filter { $0.videoID != videoID }.prefix(Self.rememberedVideos - 1)
        }
    }

    /// Calls back on the main queue. A cancelled, failed or oversized
    /// answer comes back as status 0.
    private func fetch(_ request: URLRequest, limit: Int, completion: @escaping (Int, Data) -> Void) {
        let task = session.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = data ?? Data()
            let usable = error == nil && body.count <= limit
            DispatchQueue.main.async { completion(usable ? status : 0, usable ? body : Data()) }
        }
        pending.append(task)
        task.resume()
    }
}
