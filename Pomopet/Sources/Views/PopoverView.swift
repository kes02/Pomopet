import SwiftUI
import AppKit

// MARK: - PopoverView
// 메뉴바 아이콘을 클릭했을 때 나타나는 메인 화면.
struct PopoverView: View {
    @ObservedObject var controller: PomopetController
    @ObservedObject var updater: UpdaterManager
    @ObservedObject var lang: LanguageManager
    @State private var showingStats = false
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 16) {
            header

            if controller.needsCharacter {
                CharacterUploadView(controller: controller)
            } else if showingSettings {
                SettingsView(controller: controller, updater: updater, lang: lang)
            } else if showingStats {
                StatsView(controller: controller)
            } else {
                mainContent
            }
        }
        .padding(18)
        .frame(width: 280)
    }

    // 상단 바: 제목 + 통계/설정 토글 (캐릭터 업로드 전에는 토글 숨김)
    private var header: some View {
        HStack {
            Text("Pomopet")
                .font(.headline)
            Spacer()
            if !controller.needsCharacter {
                Button {
                    showingStats = false
                    showingSettings = false
                } label: {
                    Image(systemName: "pawprint.fill")
                }
                .buttonStyle(.plain)
                .help("캐릭터")

                Button {
                    showingSettings = false
                    showingStats.toggle()
                } label: {
                    Image(systemName: "chart.bar.fill")
                }
                .buttonStyle(.plain)
                .help("통계")

                Button {
                    showingStats = false
                    showingSettings.toggle()
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .buttonStyle(.plain)
                .help("설정")
            }
        }
    }

    // 메인 화면: 캐릭터 + 스트릭/목표 + 타이머
    private var mainContent: some View {
        VStack(spacing: 14) {
            characterScreen

            // 지표 행: 연속 / 오늘 / 최고
            HStack(spacing: 8) {
                metric(title: "🔥 연속", value: "\(controller.currentStreak)일")
                metric(title: "오늘", value: "\(controller.todaySessions)/\(controller.dailyGoal)")
                metric(title: "최고", value: "\(controller.bestStreak)일")
            }

            // 일일 목표 진행바
            VStack(spacing: 4) {
                ProgressView(value: goalProgress)
                    .tint(controller.isActiveToday ? PetVisual.tint() : .gray)
                Text(goalCaption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            timerSection
        }
    }

    // 레트로 "게임 화면" 패널: 어두운 배경 + 캐릭터(활성/잠듦) + 스트릭 뱃지 + 아우라
    private var characterScreen: some View {
        let grid = PetVisual.grid() ?? []
        let tint = PetVisual.tint()
        let active = controller.isActiveToday
        let tier = StreakTier.tier(for: controller.currentStreak)
        let borderColor = tier?.color ?? tint

        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x121726), Color(hex: 0x1c2438)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
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

    private var goalProgress: Double {
        min(1.0, Double(controller.todaySessions) / Double(controller.dailyGoal))
    }

    private var goalCaption: LocalizedStringKey {
        if controller.isActiveToday {
            return "오늘 목표 달성! 연속 유지 중 🔥"
        }
        let left = max(0, controller.dailyGoal - controller.todaySessions)
        return "오늘 \(left)세션 더 하면 깨어나요"
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

    var body: some View {
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
                if let image = pickImageFile() {
                    controller.setCharacter(image)
                }
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
