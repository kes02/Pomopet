import Foundation
import SwiftUI
import AppKit
import CryptoKit

// MARK: - 친구 펫 그림 보관
//
// 친구 펫은 한 번 받아서 디스크에 저장해두고 계속 씁니다. 평소 heartbeat 에는 해시만 오가고,
// 해시가 달라졌을 때만 새로 받습니다. 그래서 친구 목록을 열 때마다 네트워크를 타지 않고,
// 서버가 죽어 있어도 친구 펫은 그대로 보입니다.

@MainActor
final class FriendPetCache {
    /// 도트로 변환한 격자를 메모리에 들고 있습니다(매번 PNG 를 다시 뜯지 않도록).
    private var grids: [String: [[Color?]]] = [:]
    /// 코드 → 지금 갖고 있는 그림의 해시
    private var hashes: [String: String]

    private static let hashesKey = "pomopet.friendPetHashes"

    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pomopet/friend-pets", isDirectory: true)
    }

    init() {
        hashes = UserDefaults.standard.dictionary(forKey: Self.hashesKey) as? [String: String] ?? [:]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 친구 펫의 색 격자. 아직 받지 않았으면 nil.
    func grid(for code: String) -> [[Color?]]? {
        if let cached = grids[code] { return cached }
        guard let image = NSImage(contentsOf: fileURL(for: code)) else { return nil }
        let grid = ImagePixelizer.colorGrid(from: image, resolution: PetVisual.renderResolution)
        grids[code] = grid
        return grid
    }

    /// 서버가 알려준 해시와 갖고 있는 게 다르면 true — 이때만 새로 받으면 됩니다.
    func needsUpdate(code: String, serverHash: String?) -> Bool {
        guard let serverHash else { return false }   // 친구가 아직 펫을 안 올림
        return hashes[code] != serverHash
    }

    func store(code: String, base64: String, hash: String) {
        guard let data = Data(base64Encoded: base64) else { return }
        try? data.write(to: fileURL(for: code), options: [.atomic])
        hashes[code] = hash
        grids[code] = nil   // 다음 조회 때 새 그림으로 다시 만듭니다
        UserDefaults.standard.set(hashes, forKey: Self.hashesKey)
    }

    func forget(code: String) {
        try? FileManager.default.removeItem(at: fileURL(for: code))
        grids[code] = nil
        hashes[code] = nil
        UserDefaults.standard.set(hashes, forKey: Self.hashesKey)
    }

    /// 친구 목록에 없는 사람들의 그림을 정리합니다(친구를 끊었거나 상대가 탈퇴한 경우).
    func pruneKeeping(codes: Set<String>) {
        for code in hashes.keys where !codes.contains(code) {
            forget(code: code)
        }
    }

    private func fileURL(for code: String) -> URL {
        directory.appendingPathComponent("\(code).png")
    }
}

// MARK: - 내 펫 내보내기
enum MyPetPayload {
    /// 내 펫을 26x26 PNG 로 줄여 base64 와 해시로 만듭니다. 캐릭터가 없으면 nil.
    /// 화면에 그릴 때 쓰는 해상도(PetVisual.renderResolution)와 같아서 친구도 나와 똑같이 보게 됩니다.
    static func current() -> (base64: String, hash: String)? {
        guard let image = CustomPetStore.loadImage(),
              let bitmap = ImagePixelizer.bitmap(from: image, side: PetVisual.renderResolution),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }

        let digest = SHA256.hash(data: png)
        let hash = digest.map { String(format: "%02x", $0) }.joined().prefix(32)
        return (png.base64EncodedString(), String(hash))
    }
}
