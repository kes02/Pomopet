import SwiftUI
import AppKit

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
