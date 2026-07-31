import Foundation
import SwiftUI
import Combine

// MARK: - FriendStore
//
// 친구 연동의 두뇌. 내 진행 상황을 서버에 올리고 친구들 상태를 받아옵니다.
//
// 원칙 두 가지:
//  1. 기본은 꺼져 있습니다. 켜기 전에는 네트워크 요청을 한 건도 보내지 않습니다.
//  2. 서버가 죽어도 앱은 멀쩡해야 합니다. 실패는 조용히 넘기고 마지막으로 받아둔 목록을 계속 보여줍니다.
//     기록의 원본은 어디까지나 내 맥의 SwiftData 이고, 서버는 서로 보여주기 위한 거울일 뿐입니다.

@MainActor
final class FriendStore: ObservableObject {

    // MARK: 발행되는 상태
    @Published private(set) var isConnected = false      // 연동을 켰는지
    @Published private(set) var myCode: String?          // 친구에게 알려줄 6자리
    @Published private(set) var friends: [FriendSummary] = []
    /// 서버에 올라가 있는 내 모습. 친구 화면에 이대로 보입니다.
    @Published private(set) var myStatus: FriendSummary?
    /// 친구 그룹 — 이 맥에만 저장되고 서버로는 가지 않습니다.
    @Published private(set) var groups: [FriendGroup] = []
    /// 동기화를 잠시 멈춘 상태. 계정·친구 관계는 그대로 두고 주고받기만 쉽니다.
    @Published private(set) var isPaused = false
    @Published private(set) var isBusy = false
    @Published private(set) var lastError: String?       // 화면에 조용히 표시할 실패 사유
    @Published var displayName: String {                 // 친구 목록에 보일 내 이름
        didSet { UserDefaults.standard.set(displayName, forKey: Self.nameKey) }
    }

    /// 방금 나를 찌른 사람. 팝오버 배너와 메뉴바 표정에 씁니다.
    @Published private(set) var incomingNudge: NudgeEvent?

    weak var controller: PomopetController?

    private let petCache = FriendPetCache()
    private var identity: FriendIdentity?
    private var timer: Timer?
    private var lastUploadedPetHash: String? {
        get { UserDefaults.standard.string(forKey: Self.petHashKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.petHashKey) }
    }
    /// 내가 방금 찌른 친구 — 버튼을 잠시 잠가둡니다(서버도 10분 제한을 겁니다).
    @Published private(set) var recentlyNudged: Set<String> = []

    private static let pausedKey = "pomopet.friendSyncPaused"
    private static let nameKey = "pomopet.friendDisplayName"
    private static let petHashKey = "pomopet.uploadedPetHash"
    private static let serverKey = "pomopet.friendServerURL"
    private static let syncInterval: TimeInterval = 60

    private var client: FriendClient {
        let url = UserDefaults.standard.string(forKey: Self.serverKey)
            .flatMap(URL.init(string:)) ?? FriendClient.defaultBaseURL
        return FriendClient(baseURL: url)
    }

    init() {
        displayName = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
        groups = FriendGroupStore.load()
        isPaused = UserDefaults.standard.bool(forKey: Self.pausedKey)
        identity = FriendIdentityStore.load()
        if let identity {
            isConnected = true
            myCode = identity.code
        }
    }

    // MARK: - 켜기 / 끄기

    /// 익명 가입 후 연동을 시작합니다. 계정·이메일·비밀번호는 없습니다.
    func connect() async {
        guard identity == nil else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let registered = try await client.register(name: displayName)
            let new = FriendIdentity(code: registered.code, secret: registered.secret)
            FriendIdentityStore.save(new)
            identity = new
            myCode = new.code
            isConnected = true
            lastError = nil
            lastUploadedPetHash = nil   // 새 계정이니 펫을 다시 올려야 합니다
            startSyncing()
            await sync()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 연동을 끕니다. 서버에서 내 계정과 친구 관계를 지우고, 받아둔 친구 펫도 정리합니다.
    func disconnect() async {
        stopSyncing()
        if let identity {
            try? await client.deleteAccount(secret: identity.secret)
        }
        FriendIdentityStore.clear()
        petCache.pruneKeeping(codes: [])
        isPaused = false
        UserDefaults.standard.set(false, forKey: Self.pausedKey)
        identity = nil
        myCode = nil
        isConnected = false
        friends = []
        incomingNudge = nil
        lastUploadedPetHash = nil
        lastError = nil
    }

    /// 코드가 엉뚱한 곳에 퍼졌을 때. 친구 관계는 그대로 유지됩니다.
    func rotateCode() async {
        guard let identity else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let newCode = try await client.rotateCode(secret: identity.secret)
            let updated = FriendIdentity(code: newCode, secret: identity.secret)
            FriendIdentityStore.save(updated)
            self.identity = updated
            myCode = newCode
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - 잠시 멈추기
    //
    // "끄기" 를 누르는 사람 대부분은 잠깐 쉬려는 것이지 탈퇴하려는 게 아닙니다.
    // 그래서 둘을 나눴습니다 — 멈춤은 주고받기만 쉬고, 계정·코드·친구 관계는 그대로 둡니다.

    func setPaused(_ paused: Bool) {
        isPaused = paused
        UserDefaults.standard.set(paused, forKey: Self.pausedKey)

        if paused {
            stopSyncing()
        } else {
            startSyncing()
            Task { await sync() }
        }
    }

    // MARK: - 주기 동기화

    func startSyncing() {
        guard isConnected, !isPaused, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.sync() }
        }
    }

    func stopSyncing() {
        timer?.invalidate()
        timer = nil
    }

    /// 내 상태를 올리고 친구 목록·찌르기를 한 번에 받아옵니다.
    /// 세션이 끝났을 때, 팝오버를 열었을 때, 그리고 1분마다 호출됩니다.
    func sync() async {
        guard !isPaused, let identity, let controller else { return }

        let payload = HeartbeatRequest(
            name: displayName,
            dayKey: controller.todayDayKey,
            sessions: controller.todaySessions,
            minutes: controller.todayMinutes,
            goal: 0,   // 하루 목표는 더 이상 쓰지 않습니다(서버 호환을 위해 필드만 유지)
            activated: controller.isActiveToday,
            streak: controller.currentStreak,
            phase: controller.phase.wireName
        )

        do {
            let response = try await client.heartbeat(secret: identity.secret, payload)
            friends = response.friends
            myStatus = response.me
            lastError = nil

            if let nudge = response.nudges?.last {
                receive(nudge)
            }
            petCache.pruneKeeping(codes: Set(response.friends.map(\.code)))
            await syncPets(secret: identity.secret, friends: response.friends)
        } catch {
            // 인터넷이 없거나 서버가 죽은 상태. 마지막으로 받아둔 목록을 그대로 두고 조용히 넘어갑니다.
            lastError = error.localizedDescription
        }
    }

    /// 내 펫이 바뀌었으면 올리고, 친구 펫이 바뀌었으면 받아옵니다.
    private func syncPets(secret: String, friends: [FriendSummary]) async {
        if let mine = MyPetPayload.current(), mine.hash != lastUploadedPetHash {
            if (try? await client.uploadPet(secret: secret, base64: mine.base64, hash: mine.hash)) != nil {
                lastUploadedPetHash = mine.hash
            }
        }

        for friend in friends where petCache.needsUpdate(code: friend.code, serverHash: friend.petHash) {
            guard let hash = friend.petHash,
                  let response = try? await client.fetchPet(secret: secret, code: friend.code)
            else { continue }
            petCache.store(code: friend.code, base64: response.pet, hash: hash)
            objectWillChange.send()   // 새 그림이 화면에 반영되도록
        }
    }

    // MARK: - 친구

    func addFriend(code: String) async -> Bool {
        guard let identity else { return false }
        let cleaned = code.uppercased().filter { $0.isLetter || $0.isNumber }
        guard cleaned.count == 6 else {
            lastError = appString("코드는 6자리예요")
            return false
        }
        isBusy = true
        defer { isBusy = false }

        do {
            _ = try await client.addFriend(secret: identity.secret, code: cleaned)
            lastError = nil
            await sync()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func removeFriend(code: String) async {
        guard let identity else { return }
        try? await client.removeFriend(secret: identity.secret, code: code)
        petCache.forget(code: code)
        assign(code: code, to: nil)   // 그룹에도 남지 않게
        await sync()
    }

    // MARK: - 그룹 (이 맥에만 저장)

    @discardableResult
    func createGroup(named name: String) -> FriendGroup {
        let group = FriendGroup(name: name)
        groups.append(group)
        FriendGroupStore.save(groups)
        return group
    }

    func renameGroup(id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = trimmed
        FriendGroupStore.save(groups)
    }

    /// 그룹만 없앱니다. 친구 관계는 그대로입니다.
    func deleteGroup(id: String) {
        groups.removeAll { $0.id == id }
        FriendGroupStore.save(groups)
    }

    /// 친구를 그룹으로 옮깁니다. groupID 가 nil 이면 그룹에서 뺍니다.
    /// 한 친구는 한 그룹에만 속합니다 — 여러 곳에 겹치면 목록에서 두 번 보여 헷갈립니다.
    func assign(code: String, to groupID: String?) {
        for index in groups.indices {
            groups[index].codes.removeAll { $0 == code }
        }
        if let groupID, let index = groups.firstIndex(where: { $0.id == groupID }) {
            groups[index].codes.append(code)
        }
        FriendGroupStore.save(groups)
    }

    func group(of code: String) -> FriendGroup? {
        groups.first { $0.codes.contains(code) }
    }

    /// 잠든 친구를 쿡 찌릅니다.
    func nudge(code: String) async {
        guard let identity, !recentlyNudged.contains(code) else { return }
        do {
            try await client.nudge(secret: identity.secret, code: code)
            recentlyNudged.insert(code)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            if case FriendClientError.tooSoon = error { recentlyNudged.insert(code) }
        }
    }

    // MARK: - 찌르기 받기

    private func receive(_ nudge: NudgeEvent) {
        incomingNudge = nudge
        // 메뉴바가 놀란 표정으로 잠깐 바뀌었다가 원래대로 돌아옵니다.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if self?.incomingNudge == nudge { self?.incomingNudge = nil }
        }
    }

    func dismissNudge() { incomingNudge = nil }

    // MARK: - 화면용 헬퍼

    func petGrid(for code: String) -> [[Color?]]? { petCache.grid(for: code) }

    /// 친구 목록에서 아직 오늘 목표를 못 채운 사람 — 찌를 수 있는 대상.
    func canNudge(_ friend: FriendSummary) -> Bool {
        !friend.activated && !recentlyNudged.contains(friend.code)
    }
}
