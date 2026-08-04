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
