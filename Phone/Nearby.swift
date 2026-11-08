import Foundation
import MultipeerConnectivity

struct Courtship: Codable {
    let sender: Mate
    let nonce: UUID
}

final class Nearby: NSObject, ObservableObject {
    private static let service = "ajolo-pixel"
    private let peer = MCPeerID(displayName: "Habitat \(UUID().uuidString.prefix(4))")
    private var browser: MCNearbyServiceBrowser?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var session: MCSession?
    private var invitation: ((Bool, MCSession?) -> Void)?

    @Published private(set) var devices: [MCPeerID] = []
    @Published private(set) var partner: MCPeerID?
    @Published private(set) var incoming: MCPeerID?
    @Published private(set) var courtship: Courtship?
    @Published private(set) var running = false
    @Published private(set) var status = ""

    func start() {
        guard !running else { return }
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: nil, serviceType: Self.service)
        advertiser.delegate = self
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.service)
        browser.delegate = self
        self.browser = browser

        running = true
        status = "Your habitat · \(peer.displayName)"
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        running = false
        invitation?(false, nil)
        invitation = nil
        incoming = nil
        browser?.stopBrowsingForPeers()
        advertiser?.stopAdvertisingPeer()
        session?.disconnect()
        browser = nil
        advertiser = nil
        session = nil
        partner = nil
        devices = []
        courtship = nil
        status = ""
    }

    func invite(_ device: MCPeerID) {
        guard let session, partner == nil else { return }
        status = "Invitation sent to \(device.displayName)"
        browser?.invitePeer(device, to: session, withContext: nil, timeout: 30)
    }

    func answer(_ accept: Bool) {
        invitation?(accept, accept ? session : nil)
        invitation = nil
        incoming = nil
    }

    @discardableResult
    func send(_ offer: Courtship) -> Bool {
        guard let session, let partner, let data = try? JSONEncoder().encode(offer) else { return false }
        do {
            try session.send(data, toPeers: [partner], with: .reliable)
            return true
        } catch {
            status = "Connection lost. Try again."
            return false
        }
    }

    private func reportFailure() {
        status = "Search stopped. Check Local Network access in Settings."
    }
}

extension Nearby: MCNearbyServiceBrowserDelegate, MCNearbyServiceAdvertiserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            guard self.browser === browser, !self.devices.contains(peerID) else { return }
            self.devices.append(peerID)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            guard self.browser === browser else { return }
            self.devices.removeAll { $0 == peerID }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            if self.browser === browser { self.reportFailure() }
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async {
            if self.advertiser === advertiser { self.reportFailure() }
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            guard self.advertiser === advertiser, self.partner == nil, self.invitation == nil else {
                invitationHandler(false, nil)
                return
            }
            self.invitation = invitationHandler
            self.incoming = peerID
        }
    }
}

extension Nearby: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            guard self.session === session else { return }
            if state == .connected {
                guard self.partner == nil else {
                    session.cancelConnectPeer(peerID)
                    return
                }
                self.partner = peerID
                self.status = "Connected to \(peerID.displayName)"
            } else if state == .notConnected, self.partner == peerID {
                self.partner = nil
                self.courtship = nil
                self.status = "Disconnected from \(peerID.displayName)"
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard data.count <= 1_024, let message = try? JSONDecoder().decode(Courtship.self, from: data),
              !message.sender.name.isEmpty, message.sender.name.count <= 20 else { return }
        DispatchQueue.main.async {
            guard self.session === session, self.partner == peerID else { return }
            self.courtship = message
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
