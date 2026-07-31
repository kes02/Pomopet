import SwiftUI
import AppKit

// MARK: - FriendsView
// 친구들의 펫과 오늘 진행 상황. 코드 6자리로 연결합니다.
struct FriendsView: View {
    @ObservedObject var store: FriendStore
    @State private var codeInput = ""
    @State private var nameInput = ""
    @State private var didCopy = false
    @State private var didRename = false
    @State private var addingGroup = false
    @State private var confirmingRotate = false
    @State private var confirmingDisconnect = false
    @State private var newGroupName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            if store.isConnected {
                if !store.friends.isEmpty { groupBar }
                friendList
                Divider()
                myPreviewRow
                myNameRow
                myCodeRow
                addFriendRow

                Divider()
                disconnectRow
            } else {
                intro
            }

            if let error = store.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            nameInput = store.displayName
            Task { await store.sync() }
        }
    }

    // MARK: 연동 전 — 소개와 이름 정하기

    private var intro: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("친구와 같이 키우기")
                .font(.system(size: 15, weight: .semibold))

            Text("서로 6자리 코드를 입력하면 연결돼요.\n친구 펫이 깨어 있는지 한눈에 보이고, 잠들어 있으면 쿡 찌를 수 있어요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            TextField("친구에게 보일 이름", text: $nameInput)
                .textFieldStyle(.roundedBorder)
                .font(.callout)

            Button {
                store.displayName = nameInput.trimmingCharacters(in: .whitespaces)
                Task { await store.connect() }
            } label: {
                Label("친구 연동 켜기", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isBusy || nameInput.trimmingCharacters(in: .whitespaces).isEmpty)

            Text("계정을 만들지 않아요. 오늘 몇 세션 했는지와 펫 그림만 오갑니다.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    // MARK: 그룹 만들기
    //
    // 우클릭 메뉴에만 두면 있는 줄도 모릅니다. 목록 위에 보이는 버튼을 둡니다.

    private var groupBar: some View {
        HStack(spacing: 6) {
            Text("친구")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if addingGroup {
                TextField("그룹 이름", text: $newGroupName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .frame(width: 120)
                    .onSubmit { commitNewGroup() }

                Button {
                    addingGroup = false
                    newGroupName = ""
                } label: {
                    Image(systemName: "xmark").font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            } else {
                Button {
                    addingGroup = true
                } label: {
                    Label("그룹 만들기", systemImage: "plus")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("만든 뒤 친구를 우클릭해서 옮기면 돼요")
            }
        }
    }

    private func commitNewGroup() {
        let name = newGroupName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { store.createGroup(named: name) }
        newGroupName = ""
        addingGroup = false
    }

    // MARK: 친구 목록

    @ViewBuilder
    private var friendList: some View {
        if store.friends.isEmpty {
            VStack(spacing: 6) {
                Text("아직 친구가 없어요")
                    .font(.callout)
                Text("아래 내 코드를 친구에게 알려주세요")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        } else {
            // 넘칠 때만 스크롤합니다.
            //
            // 예전에는 높이를 미리 계산해서 ScrollView 에 물려줬는데, 계산이 실제 렌더 높이와
            // 조금만 어긋나도 마지막 줄이 잘려 "만들었는데 안 보인다" 가 됐습니다.
            // 이제 들어갈 만하면 그냥 쌓아 두고(스크롤 없음), 많아졌을 때만 스크롤을 씌웁니다.
            if needsScroll {
                ScrollView { groupStack }
                    .frame(maxHeight: Self.maxListHeight)
            } else {
                groupStack
            }
        }
    }

    /// 그룹 덩어리들. 그룹이 없으면 머리글 없이 친구만 쭉 나옵니다.
    private var groupStack: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(sections, id: \.id) { section in
                GroupBlock(title: section.title, groupID: section.groupID,
                           friends: section.friends, store: store)
            }

            if !store.groups.isEmpty {
                Text("친구 위의 폴더 아이콘으로 그룹을 옮겨요")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    /// 스크롤이 필요한 시점 — 그룹 머리글까지 세어 이 높이를 넘을 때만.
    private var needsScroll: Bool {
        let headers = sections.filter { $0.title != nil }.count
        let rows = store.friends.count
        return FriendRow.contentHeight(headers: headers, rows: rows) > Self.maxListHeight
    }

    /// 스크롤 없이 보여줄 최대 높이.
    /// 그룹 머리글 3개 + 친구 6줄이 들어갑니다 — 어떤 조합이든 최소 3줄은 스크롤 없이 보입니다.
    private static let maxListHeight: CGFloat = 460

    // MARK: 친구 화면에 보이는 내 모습
    //
    // "친구한테 내가 어떻게 보이지?" 가 바로 안 보이면 이름을 고칠 엄두가 안 납니다.
    // 서버에 올라가 있는 내 기록(myStatus)을 친구 목록과 똑같은 모양으로 그대로 보여줍니다.

    @ViewBuilder
    private var myPreviewRow: some View {
        if let me = store.myStatus {
            VStack(alignment: .leading, spacing: 4) {
                Text("친구에게 이렇게 보여요")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    FriendPetThumb(grid: PetVisual.grid(), awake: me.activated)

                    // 친구 줄과 같은 배치 — 이름 오른쪽에 불꽃·시간을 붙입니다.
                    HStack(spacing: 5) {
                        Text(verbatim: me.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(verbatim: "🔥\(me.streak)")
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(focusMinutesLabel(me.minutes))
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.10))
                )
            }
        }
    }

    // MARK: 내 이름
    // 바꾸면 곧바로 서버에 올라가서 친구 목록에도 반영됩니다.

    private var myNameRow: some View {
        HStack(spacing: 6) {
            Text("내 이름")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("이름", text: $nameInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused($nameFocused)
                .onSubmit { commitName() }

            if didRename {
                Image(systemName: "checkmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            } else if nameChanged {
                Button("저장") { commitName() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        // 입력란 밖을 눌러 포커스가 빠질 때도 저장합니다(저장 버튼을 못 보고 지나치지 않게).
        .onChange(of: nameFocused) { _, focused in
            if !focused, nameChanged { commitName() }
        }
    }

    private var nameChanged: Bool {
        let trimmed = nameInput.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed != store.displayName
    }

    private func commitName() {
        let trimmed = nameInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            nameInput = store.displayName   // 빈 이름은 되돌립니다
            return
        }
        guard trimmed != store.displayName else { return }

        store.displayName = trimmed
        Task {
            await store.sync()   // 친구들이 바로 새 이름을 보도록
            didRename = true
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            didRename = false
        }
    }

    // MARK: 내 코드

    private var myCodeRow: some View {
        HStack(spacing: 6) {
            Text("내 코드")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(verbatim: store.myCode ?? "······")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .textSelection(.enabled)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(store.myCode ?? "", forType: .string)
                didCopy = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    didCopy = false
                }
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.plain)
            .foregroundStyle(didCopy ? .green : .secondary)
            .help("코드 복사")

            Spacer()

            // 코드 줄에 딸린 동작이라 같은 줄 오른쪽 끝에 둡니다.
            // 예전 코드는 되살릴 수 없어서 한 번 더 물어봅니다.
            Button(confirmingRotate ? "정말 바꿀까요?" : "코드 새로 받기") {
                if confirmingRotate {
                    Task { await store.rotateCode() }
                    confirmingRotate = false
                } else {
                    confirmingRotate = true
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("예전 코드는 못 쓰게 됩니다. 이미 연결된 친구는 그대로예요")
        }
    }

    // MARK: 연동 끄기
    // 되돌릴 수 없는 동작이라 맨 아래에 두고 한 번 더 물어봅니다.

    private var disconnectRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("친구 연동")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                // 멈춘 상태는 버튼 글씨만으로는 놓치기 쉬워서 표시를 남겨둡니다.
                if store.isPaused {
                    Text("멈춤")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.orange.opacity(0.18)))
                }

                Spacer()

                // 되돌릴 수 있는 쪽(멈추기)을 먼저, 되돌릴 수 없는 쪽(끄기)을 오른쪽 끝에.
                Button(store.isPaused ? "다시 시작" : "잠시 멈추기") {
                    store.setPaused(!store.isPaused)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("계정과 친구는 그대로 두고 주고받기만 쉽니다")

                Button(confirmingDisconnect ? "정말 끌까요?" : "연동 끄기", role: .destructive) {
                    if confirmingDisconnect {
                        Task { await store.disconnect() }
                        confirmingDisconnect = false
                    } else {
                        confirmingDisconnect = true
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            }

            if store.isPaused {
                Text("친구에게 내 상태가 올라가지 않고, 친구 목록도 갱신되지 않아요")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if confirmingDisconnect {
                Text("친구 목록에서도 사라지고 코드가 바뀝니다. 되돌릴 수 없어요")
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 친구 추가

    private var addFriendRow: some View {
        HStack(spacing: 6) {
            TextField("친구 코드 6자리", text: $codeInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit { submitCode() }

            Button("추가") { submitCode() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.isBusy || codeInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: 그룹별로 나누기

    private struct Section {
        let id: String
        let title: String?
        let groupID: String?
        let friends: [FriendSummary]
    }

    private var sections: [Section] {
        guard !store.groups.isEmpty else {
            return [Section(id: "all", title: nil, groupID: nil, friends: store.friends)]
        }

        // 비어 있는 그룹도 보여줍니다 — 만들자마자 사라지면 만들어진 줄 모릅니다.
        var result: [Section] = []
        for group in store.groups {
            let members = store.friends.filter { group.codes.contains($0.code) }
            result.append(Section(id: group.id, title: group.name, groupID: group.id, friends: members))
        }

        let assigned = Set(store.groups.flatMap(\.codes))
        let rest = store.friends.filter { !assigned.contains($0.code) }
        if !rest.isEmpty {
            result.append(Section(id: "none", title: appString("그룹 없음"), groupID: nil, friends: rest))
        }
        return result
    }

    private func submitCode() {
        let code = codeInput
        Task {
            if await store.addFriend(code: code) { codeInput = "" }
        }
    }
}

/// 오늘 집중한 시간을 사람이 읽는 형태로.
/// 문자열 카탈로그를 타도록 LocalizedStringKey 로 돌려줍니다(영문 전환 시 번역됨).
func focusMinutesLabel(_ minutes: Int) -> LocalizedStringKey {
    let h = minutes / 60
    let m = minutes % 60
    return h > 0 ? "\(h)시간 \(m)분" : "\(m)분"
}

// MARK: - FriendRow
// 친구 한 줄: 펫 + 이름 + 오늘 진행 + 스트릭 (+ 잠들어 있으면 찌르기)
struct FriendRow: View {
    let friend: FriendSummary
    @ObservedObject var store: FriendStore
    @State private var hovering = false
    @State private var confirmingRemove = false

    /// 목록에서 줄 사이 간격.
    static let spacing: CGFloat = 8
    /// 한 줄 높이 (펫 38 + 위아래 여백).
    static let rowHeight: CGFloat = 48
    /// 그룹 머리글 한 줄 높이.
    static let headerHeight: CGFloat = 24
    /// 한 그룹 안에서 스크롤 없이 보여줄 친구 수. 그 이상은 그룹 안에서 스크롤됩니다.
    static let rowsPerGroup = 3

    /// 머리글 n개 + 친구 m줄이 차지하는 높이.
    static func contentHeight(headers: Int, rows: Int) -> CGFloat {
        let items = max(1, headers + rows)
        return CGFloat(headers) * headerHeight
            + CGFloat(rows) * rowHeight
            + CGFloat(items - 1) * spacing
    }

    var body: some View {
        HStack(spacing: 10) {
            FriendPetThumb(grid: store.petGrid(for: friend.code), awake: friend.activated)

            VStack(alignment: .leading, spacing: 2) {
                // 이름 → 불꽃 → 집중 시간 순으로 붙여 놓습니다.
                //
                // 마우스를 올리면 오른쪽에 버튼 세 개가 나타나 자리가 좁아지므로,
                // 그동안은 불꽃·시간을 숨깁니다. 안 그러면 글자가 눌려 잘립니다.
                HStack(spacing: 5) {
                    Text(verbatim: friend.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)

                    if !hovering {
                        Text(verbatim: "🔥\(friend.streak)")
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(focusMinutesLabel(friend.minutes))
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                if friend.isFocusing {
                    Text("집중 중")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.25)))
                }
            }

            Spacer()

            if confirmingRemove {
                // 실수로 지우는 걸 막습니다 — 한 번 더 물어봅니다.
                Text("삭제할까요?")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Button("삭제") {
                    Task { await store.removeFriend(code: friend.code) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(.red)
                Button {
                    confirmingRemove = false
                } label: {
                    Image(systemName: "xmark").font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            } else {
                if hovering {
                    Menu {
                        ForEach(store.groups) { group in
                            Button(group.name) { store.assign(code: friend.code, to: group.id) }
                        }
                        if !store.groups.isEmpty { Divider() }
                        Button("새 그룹 만들기…") {
                            let group = store.createGroup(named: appString("새 그룹"))
                            store.assign(code: friend.code, to: group.id)
                        }
                        if store.group(of: friend.code) != nil {
                            Divider()
                            Button("그룹에서 빼기") { store.assign(code: friend.code, to: nil) }
                        }
                    } label: {
                        Image(systemName: "folder").font(.system(size: 10))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 18)
                    .help("그룹 옮기기")
                }

                if store.canNudge(friend) {
                    Button {
                        Task { await store.nudge(code: friend.code) }
                    } label: {
                        Text("쿡")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("잠든 펫을 깨워주세요")
                }

                if hovering {
                    Button {
                        confirmingRemove = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("친구 끊기")
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(hovering ? 0.06 : 0.03))
        )
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
        .contextMenu {
            Menu("그룹으로 옮기기") {
                ForEach(store.groups) { group in
                    Button(group.name) { store.assign(code: friend.code, to: group.id) }
                }
                if !store.groups.isEmpty { Divider() }
                Button("새 그룹 만들기…") {
                    let group = store.createGroup(named: appString("새 그룹"))
                    store.assign(code: friend.code, to: group.id)
                }
                if store.group(of: friend.code) != nil {
                    Divider()
                    Button("그룹에서 빼기") { store.assign(code: friend.code, to: nil) }
                }
            }
        }
    }
}

// MARK: - GroupBlock
//
// 그룹 하나(머리글 + 그 안의 친구들).
//
// 드래그로 옮기는 방식도 만들어봤지만 메뉴바 팝오버 안에서는 동작하지 않았습니다.
// 이 팝오버는 잠깐 떴다 사라지는 창이라 macOS 드래그 세션에 제대로 참여하지 못합니다.
// 대신 친구 줄의 폴더 버튼으로 옮깁니다.
struct GroupBlock: View {
    let title: String?
    let groupID: String?
    let friends: [FriendSummary]
    @ObservedObject var store: FriendStore

    var body: some View {
        VStack(alignment: .leading, spacing: FriendRow.spacing) {
            if let title {
                GroupHeader(title: title, groupID: groupID,
                            memberCount: friends.count, store: store)
            }

            if friends.isEmpty {
                // 빈 그룹도 끌어다 놓을 만큼은 자리를 차지해야 합니다.
                Text("비어 있어요")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            } else {
                ForEach(friends) { friend in
                    FriendRow(friend: friend, store: store)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - GroupHeader
//
// 그룹 이름 줄. 마우스를 올리면 연필(이름 바꾸기)과 휴지통(그룹 없애기)이 나타납니다.
// 더블클릭·우클릭 같은 숨은 방법은 두지 않았습니다 — 있는 줄 모르면 없는 기능이나 마찬가지고,
// 같은 일을 하는 길이 여럿이면 어느 것도 확실히 익혀지지 않습니다.
struct GroupHeader: View {
    let title: String
    let groupID: String?
    let memberCount: Int
    @ObservedObject var store: FriendStore

    @State private var renaming = false
    @State private var draft = ""
    @State private var hovering = false
    @State private var confirmingDelete = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            if renaming, let groupID {
                TextField("그룹 이름", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .frame(maxWidth: 140)
                    .focused($focused)
                    .onSubmit { commit(groupID) }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { commit(groupID) }
                    }

            } else {
                Text(verbatim: title)
                    .font(.system(size: 11, weight: .semibold))
                Text(verbatim: "\(memberCount)")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                if groupID != nil, hovering, !confirmingDelete {
                    Button { startRenaming() } label: {
                        Image(systemName: "pencil").font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("이름 바꾸기")

                    Button { confirmingDelete = true } label: {
                        Image(systemName: "trash").font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("그룹 없애기 (친구는 그대로 남아요)")
                }

                if confirmingDelete, let groupID {
                    Text("그룹만 없앨까요?")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Button("없애기") {
                        store.deleteGroup(id: groupID)
                        confirmingDelete = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .tint(.red)
                    Button {
                        confirmingDelete = false
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .frame(height: FriendRow.headerHeight)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private func startRenaming() {
        draft = title
        renaming = true
        focused = true
    }

    private func commit(_ groupID: String) {
        guard renaming else { return }
        store.renameGroup(id: groupID, to: draft)
        renaming = false
    }
}

// MARK: - FriendPetThumb
// 친구 펫을 작게. 아직 못 받았거나 안 올렸으면 실루엣.
struct FriendPetThumb: View {
    let grid: [[Color?]]?
    let awake: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(hex: 0x121726))
                .frame(width: 38, height: 38)

            if let grid, !grid.isEmpty {
                ColorGridView(grid: grid, size: 33)
                    .saturation(awake ? 1.0 : 0.1)
                    .opacity(awake ? 1.0 : 0.45)
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
    }
}

// MARK: - NudgeBanner
// 친구가 나를 찔렀을 때 팝오버 위쪽에 잠깐 뜨는 줄.
struct NudgeBanner: View {
    let nudge: NudgeEvent
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: "🫵")
            Text("\(nudge.displayName)님이 깨웠어요")
                .font(.caption)
                .fontWeight(.medium)
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark").font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.18))
        )
    }
}
