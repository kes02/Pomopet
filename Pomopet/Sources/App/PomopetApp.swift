import SwiftUI
import SwiftData

// MARK: - PomopetApp
// 앱의 진입점. macOS 메뉴바에만 존재하는 앱입니다 (Dock 아이콘 없음).
@main
struct PomopetApp: App {
    // 앱 전역에서 공유되는 컨트롤러
    @StateObject private var controller = PomopetController()

    // Sparkle 자동 업데이트
    @StateObject private var updater = UpdaterManager()

    // 앱 내 언어 전환 (시스템 언어와 무관하게 ko/en)
    @StateObject private var lang = LanguageManager()

    // SwiftData 저장소 컨테이너
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(
                for: DailyRecord.self, AppStats.self
            )
        } catch {
            fatalError("SwiftData 컨테이너 생성 실패: \(error)")
        }
    }

    var body: some Scene {
        // MenuBarExtra: 메뉴바에 아이콘을 띄우는 macOS 13+ API
        MenuBarExtra {
            PopoverView(controller: controller, updater: updater, lang: lang)
                .environment(\.locale, lang.locale)   // 선택 언어로 포맷/번역 갱신
                .modelContainer(modelContainer)
                .onAppear {
                    // 컨트롤러에 SwiftData 컨텍스트 연결 (최초 1회)
                    controller.attach(context: modelContainer.mainContext)
                }
        } label: {
            // 메뉴바에 표시되는 라벨: 공부 상태(활성/잠듦) 심볼 + 연속일
            MenuBarLabel(controller: controller)
        }
        .menuBarExtraStyle(.window) // 팝오버 형태 (.menu가 아닌 커스텀 뷰)
    }
}

// MARK: - MenuBarLabel
// 메뉴바에 실제로 보이는 부분. 캐릭터가 깨어있으면 불꽃 + 연속일, 자고 있으면 달.
struct MenuBarLabel: View {
    @ObservedObject var controller: PomopetController

    var body: some View {
        HStack(spacing: 4) {
            if controller.phase.isCountingDown {
                // 집중·휴식 진행 중 — 표정 대신 남은 시간만
                Text(controller.timeString)
                    .monospacedDigit()
            } else {
                // 유휴 — 오늘 세션 0=잠듦, ≥1=깨움
                Text(controller.menuBarFace)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                if controller.isActiveToday && controller.currentStreak > 0 {
                    Text("\(controller.currentStreak)")
                        .monospacedDigit()
                }
            }
        }
    }
}
