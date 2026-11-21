// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import CoreBluetooth
import Foundation

@MainActor
final class BoseHeadphonesService: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate {
    static let shared = BoseHeadphonesService()

    enum Phase: Equatable {
        case idle, checkingBluetooth, finding, choosing, connecting, ready
        case bluetoothOff, permissionDenied, unsupported, noDevices, failed(BoseHeadphoneError)
    }

    @Published private(set) var phase = Phase.idle
    @Published private(set) var devices: [BoseHeadphoneDevice] = []
    @Published private(set) var device: BoseHeadphoneDevice?
    @Published private(set) var status: BoseHeadphoneStatus?
    @Published private(set) var busy = false

    private var panels: Set<UUID> = []
    private var bluetooth: CBCentralManager?
    private var connection: BoseHeadphoneTransport?
    private var connectionID: UUID?
    private var operation: Task<Void, Never>?
    private var closing: Task<Void, Never>?
    /// The headset last opened, preferred when several are connected.
    private var preferredDeviceID: String?

    /// The island hides its page every time it collapses; keeping the link
    /// this long makes reopening it instant instead of a reconnect.
    private static let lingerAfterClose = Duration.seconds(30)

    private var panelIsActive: Bool { !panels.isEmpty && AppFeature.qcControl.isAvailable }

    func panelOpened(_ id: UUID) {
        let wasClosed = panels.isEmpty
        panels.insert(id)
        guard wasClosed else { return }
        closing?.cancel()
        closing = nil
        guard phase != .ready, operation == nil else { return }
        if let bluetooth {
            centralManagerDidUpdateState(bluetooth)
        } else if CBManager.authorization == .allowedAlways {
            // Access was granted before, so this neither prompts nor pages:
            // discovery lists only headphones already connected to this Mac.
            findHeadphones()
        }
    }

    func panelClosed(_ id: UUID) {
        panels.remove(id)
        guard panels.isEmpty else { return }
        closing?.cancel()
        closing = Task { [weak self] in
            try? await Task.sleep(for: Self.lingerAfterClose)
            guard let self, !Task.isCancelled, self.panels.isEmpty else { return }
            self.closing = nil
            self.closeAfterLinger()
        }
    }

    private func closeAfterLinger() {
        stopConnection()
        devices = []
        // The system prompt can take focus from the popover. Let it finish
        // without keeping a headphone connection or starting discovery.
        if bluetooth != nil, CBManager.authorization == .notDetermined {
            phase = .checkingBluetooth
        } else {
            releaseBluetooth()
        }
    }

    func findHeadphones() {
        guard panelIsActive, !busy else { return }
        if CBManager.authorization == .denied || CBManager.authorization == .restricted {
            phase = .permissionDenied
            return
        }
        if let bluetooth {
            centralManagerDidUpdateState(bluetooth)
        } else {
            phase = .checkingBluetooth
            bluetooth = CBCentralManager(delegate: self, queue: nil, options: [
                CBCentralManagerOptionShowPowerAlertKey: false
            ])
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === bluetooth else { return }
        let authorization = CBManager.authorization
        guard panelIsActive else {
            if authorization != .notDetermined || central.state == .unsupported {
                stopConnection()
                devices = []
                releaseBluetooth()
            }
            return
        }
        stopConnection()
        devices = []
        if authorization == .denied || authorization == .restricted {
            phase = .permissionDenied
            return
        }
        switch central.state {
        case .poweredOn:
            if authorization == .allowedAlways { discover() }
            else { phase = .checkingBluetooth }
        case .poweredOff: phase = .bluetoothOff
        case .unauthorized: phase = .permissionDenied
        case .unsupported: phase = .unsupported
        case .unknown, .resetting: phase = .checkingBluetooth
        @unknown default: phase = .unsupported
        }
    }

    private func releaseBluetooth() {
        bluetooth?.delegate = nil
        bluetooth = nil
        phase = .idle
    }

    func connect(to id: String) {
        guard let target = devices.first(where: { $0.id == id }),
              bluetooth?.state == .poweredOn,
              CBManager.authorization == .allowedAlways, panelIsActive, !busy else { return }
        run { try await self.open(target) }
    }

    func selectMode(_ id: UInt8) {
        useConnection { commands, status in try await commands.select(id, from: status) }
    }

    func setNoiseCancellation(_ level: Int) {
        useConnection { commands, status in try await commands.setLevel(level, from: status) }
    }

    private func discover() {
        phase = .finding
        run {
            let paired = await BoseHeadphoneTransport.pairedHeadphones()
            try Task.checkCancellation()
            self.devices = paired
            let remembered = paired.first { $0.id == self.preferredDeviceID }
            if let target = remembered ?? (paired.count == 1 ? paired.first : nil) {
                try await self.open(target)
            } else {
                self.phase = paired.isEmpty ? .noDevices : .choosing
            }
        }
    }

    private func open(_ target: BoseHeadphoneDevice) async throws {
        connection?.disconnect()
        status = nil
        device = target
        preferredDeviceID = target.id
        phase = .connecting
        let id = UUID()
        connectionID = id
        let link = BoseHeadphoneTransport { [weak self] in
            Task { @MainActor in
                guard let self, self.connectionID == id else { return }
                self.stopConnection()
                self.phase = .failed(.disconnected)
            }
        }
        connection = link
        try await link.connect(to: target.id)
        let snapshot = try await commands(over: link).read()
        try Task.checkCancellation()
        status = snapshot
        phase = .ready
    }

    private func useConnection(_ body: @escaping (BoseHeadphoneCommands, BoseHeadphoneStatus) async throws -> BoseHeadphoneStatus) {
        guard let connection, let status, phase == .ready else { return }
        run {
            let snapshot = try await body(self.commands(over: connection), status)
            try Task.checkCancellation()
            self.status = snapshot
        }
    }

    private func commands(over link: BoseHeadphoneTransport) -> BoseHeadphoneCommands {
        BoseHeadphoneCommands { command in
            try Task.checkCancellation()
            // Not tied to an open page: a change started just before the
            // island collapsed still finishes during the linger.
            guard AppFeature.qcControl.isAvailable, self.connection === link, self.bluetooth?.state == .poweredOn,
                  CBManager.authorization == .allowedAlways else { throw CancellationError() }
            return try await link.send(command)
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        guard panelIsActive, operation == nil else { return }
        busy = true
        operation = Task {
            do {
                try await work()
            } catch {
                guard !Task.isCancelled else { return }
                dropLink()
                phase = .failed(error as? BoseHeadphoneError ?? .disconnected)
            }
            guard !Task.isCancelled else { return }
            operation = nil
            busy = false
        }
    }

    private func dropLink() {
        connectionID = nil
        connection?.disconnect()
        connection = nil
        status = nil
        device = nil
    }

    private func stopConnection() {
        operation?.cancel()
        operation = nil
        busy = false
        dropLink()
    }
}
