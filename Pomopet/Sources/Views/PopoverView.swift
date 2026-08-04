import SwiftUI
import AppKit

// MARK: - PopoverView
// 메뉴바 아이콘을 클릭했을 때 나타나는 메인 화면.
struct PopoverView: View {
    @ObservedObject var controller: PomopetController
    @ObservedObject var updater: UpdaterManager
    @ObservedObject var lang: LanguageManager
    @ObservedObject var friends: FriendStore
    @ObservedObject var workWatcher: WorkAppWatcher
    @State private var tab: Tab = .pet

    enum Tab { case pet, stats, friends, settings }

    var body: some View {
        VStack(spacing: 16) {
            header

            // 친구가 찔렀으면 어느 화면에 있든 위쪽에 알려줍니다.
            if let nudge = friends.incomingNudge {
                NudgeBanner(nudge: nudge) { friends.dismissNudge() }
            }

            if controller.needsCharacter {
                CharacterUploadView(controller: controller)
            } else {
                switch tab {
                case .pet: mainContent
                case .stats: StatsView(controller: controller)
                case .friends: FriendsView(store: friends)
                case .settings: SettingsView(controller: controller, updater: updater, lang: lang,
                                            workWatcher: workWatcher)
                }
            }
        }
        .padding(18)
        .frame(width: 280)
        .onAppear {
            // 팝오버를 열 때마다 친구 상태를 한 번 새로 받아옵니다.
            Task { await friends.sync() }
        }
    }

    // 상단 바: 제목 + 통계/설정 토글 (캐릭터 업로드 전에는 토글 숨김)
    private var header: some View {
        HStack {
            Text("Pomopet")
                .font(.headline)
            Spacer()
            if !controller.needsCharacter {
                tabButton(.pet, icon: "pawprint.fill", help: "캐릭터")
                tabButton(.stats, icon: "chart.bar.fill", help: "통계")
                tabButton(.friends, icon: "person.2.fill", help: "친구")
                tabButton(.settings, icon: "gearshape.fill", help: "설정")
            }
        }
    }

    // 상단 탭 버튼. 지금 보고 있는 탭은 진하게, 나머지는 흐리게.
    private func tabButton(_ target: Tab, icon: String, help: LocalizedStringKey) -> some View {
        Button {
            tab = target
        } label: {
            Image(systemName: icon)
                .foregroundStyle(tab == target ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // 메인 화면: 캐릭터 + 스트릭/목표 + 타이머
    private var mainContent: some View {
        VStack(spacing: 14) {
            characterScreen

            // 지표 행: 연속 / 오늘 집중 시간 / 최고
            HStack(spacing: 8) {
                metric(title: "🔥 연속", value: "\(controller.currentStreak)일")
                metric(title: "오늘", value: focusMinutesLabel(controller.todayMinutes))
                metric(title: "최고", value: "\(controller.bestStreak)일")
            }

            Text(todayCaption)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            timerSection
        }
    }

    // 레트로 "게임 화면" 패널: 어두운 배경 + 캐릭터(활성/잠듦) + 스트릭 뱃지 + 아우라
    private var characterScreen: some View {
        let grid = PetVisual.grid() ?? []
        let tint = PetVisual.tint()
        let active = controller.isPetAwake
        let tier = StreakTier.tier(for: controller.currentStreak)
        let borderColor = tier?.color ?? tint

        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(PetScreen.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(borderColor.opacity(active ? 0.7 : 0.3), lineWidth: 1.5)
                )

            // 마일스톤 아우라 (연속일이 쌓이면 캐릭터 둘레가 빛남)
            if active, let tier = tier {
                Circle()
                    .stroke(tier.color.opacity(0.6), lineWidth: 2)
                    .frame(width: 112, height: 112)
                    .blur(radius: 1)
            }

            CharacterView(grid: grid, tint: tint, active: active, size: 96)

            VStack {
                HStack(alignment: .top) {
                    // 스트릭 뱃지
                    HStack(spacing: 3) {
                        Text("🔥")
                        Text("\(controller.currentStreak)")
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.black.opacity(0.35)))

                    Spacer()

                    if let tier = tier {
                        Text(tier.name)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(tier.color)
                    }
                }
                Spacer()
                if !active {
                    Text("오늘 공부하면 깨어나요")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(8)
        }
        .frame(height: 140)
    }

    private func metric(title: LocalizedStringKey, value: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var todayCaption: LocalizedStringKey {
        if controller.phase == .focusing { return "집중하는 동안 펫도 깨어 있어요" }
        return controller.isActiveToday
            ? "오늘도 집중했어요! 연속 유지 중 🔥"
            : "오늘 집중하면 펫이 깨어나요"
    }

    // 타이머 영역: 현재 단계에 따라 다른 버튼/표시
    @ViewBuilder
    private var timerSection: some View {
        switch controller.phase {
        case .idle:
            VStack(spacing: 10) {
                Text("준비됨")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    controller.startFocus()
                } label: {
                    Label("집중 시작", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

        case .focusing:
            VStack(spacing: 10) {
                Text(controller.timeString)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("집중 중…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("중단", role: .destructive) {
                    controller.stop()
                }
                .buttonStyle(.bordered)
            }

        case .breakReady:
            VStack(spacing: 10) {
                Text("집중 완료! 잘했어요 🎉")
                    .font(.callout)
                if controller.isActiveToday {
                    Text("🔥 \(controller.currentStreak)일 연속!")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                }
                HStack {
                    Button("휴식 시작") { controller.startBreak() }
                        .buttonStyle(.borderedProminent)
                    Button("건너뛰기") { controller.skipBreak() }
                        .buttonStyle(.bordered)
                }
            }

        case .resting:
            VStack(spacing: 10) {
                Text(controller.timeString)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("휴식 중…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("휴식 종료") {
                    controller.skipBreak()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - StreakTier
// 연속일에 따른 마일스톤 등급. 진화 대신 캐릭터 둘레 아우라로 "성장"을 표현.
struct StreakTier {
    let name: String
    let color: Color
    let minDays: Int

    static let all: [StreakTier] = [
        StreakTier(name: "DIAMOND", color: Color(hex: 0x6fe3ff), minDays: 100),
        StreakTier(name: "GOLD", color: Color(hex: 0xffd23f), minDays: 30),
        StreakTier(name: "SILVER", color: Color(hex: 0xc9d2dc), minDays: 7),
        StreakTier(name: "BRONZE", color: Color(hex: 0xcd8b5b), minDays: 3),
    ]

    static func tier(for streak: Int) -> StreakTier? {
        all.first { streak >= $0.minDays }
    }
}

// MARK: - CharacterUploadView
// 첫 실행: 키울 캐릭터 이미지를 올리는 화면.
struct CharacterUploadView: View {
    @ObservedObject var controller: PomopetController
    @State private var pending: NSImage?

    var body: some View {
        if let pending {
            CharacterPreview(
                image: pending,
                onConfirm: { final in
                    controller.setCharacter(final)
                    self.pending = nil
                },
                onRetry: { self.pending = pickImageFile() ?? pending }
            )
            // 다른 이미지를 고르면 미리보기를 새로 시작합니다.
            // 이게 없으면 SwiftUI 가 같은 뷰를 재사용해, 앞서 배경을 지운 결과가 그대로 남습니다.
            .id(ObjectIdentifier(pending))
        } else {
            picker
        }
    }

    private var picker: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("키울 캐릭터를 올려줘")
                .font(.system(size: 15, weight: .semibold))

            Text("좋아하는 캐릭터 이미지를 도트로 바꿔서,\n매일 공부하면 깨어나고 연속 기록이 쌓여요")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                pending = pickImageFile()
            } label: {
                Label("이미지 선택", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text("투명 배경 PNG(누끼)면 캐릭터만 또렷하게 떠요")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}
