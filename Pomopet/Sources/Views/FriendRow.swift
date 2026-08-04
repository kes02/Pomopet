import SwiftUI
import AppKit

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
