import SwiftUI

// MARK: - PopoverView
// 메뉴바 아이콘을 클릭했을 때 나타나는 메인 화면.
struct PopoverView: View {
    @ObservedObject var controller: PomopetController
    @State private var showingStats = false
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 16) {
            header

            if showingSettings {
                SettingsView(controller: controller)
            } else if showingStats {
                StatsView(controller: controller)
            } else {
                mainContent
            }
        }
        .padding(18)
        .frame(width: 280)
    }

    // 상단 바: 제목 + 통계/설정 토글
    private var header: some View {
        HStack {
            Text("Pomopet")
                .font(.headline)
            Spacer()
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

    // 메인 화면: 생물 + 진행 + 타이머
    private var mainContent: some View {
        VStack(spacing: 14) {
            if let creature = controller.currentCreature {
                creatureScreen(creature)

                VStack(spacing: 4) {
                    Text(creature.species.name)
                        .font(.system(size: 15, weight: .semibold))
                    Text(creature.stage.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // 진화 진행바
                VStack(spacing: 4) {
                    ProgressView(value: creature.progressWithinStage)
                        .tint(creature.species.color)
                    if let remaining = creature.sessionsToNextStage {
                        Text("다음 진화까지 \(remaining)세션")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("완전체! 곧 새 알이 부화해요")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            timerSection
        }
    }

    // 레트로 "게임 화면" 패널: 어두운 배경 + 픽셀 생물 + Lv 뱃지
    private func creatureScreen(_ creature: Creature) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x121726), Color(hex: 0x1c2438)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(creature.species.color.opacity(0.45), lineWidth: 1.5)
                )

            CreatureView(species: creature.species, stage: creature.stage, size: 96)

            // 좌상단 Lv 뱃지
            VStack {
                HStack {
                    Text("Lv.\(creature.level)")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(creature.species.color))
                    Spacer()
                    // 집중 완료 직후엔 레벨업 연출
                    if controller.phase == .breakReady {
                        Text("LV UP!")
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.yellow)
                    }
                }
                Spacer()
            }
            .padding(8)
        }
        .frame(height: 132)
    }

    // 타이머 영역: 현재 단계에 따라 다른 버튼/표시
    @ViewBuilder
    private var timerSection: some View {
        switch controller.phase {
        case .idle:
            VStack(spacing: 10) {
                Text(controller.timeString.isEmpty ? "준비됨" : "준비됨")
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
