import SwiftUI
import SwiftData

// MARK: - PomopetApp
// 앱의 진입점. macOS 메뉴바에만 존재하는 앱입니다 (Dock 아이콘 없음).
@main
struct PomopetApp: App {
    // 앱 전역에서 공유되는 컨트롤러
    @StateObject private var controller = PomopetController()

    // 인앱 업데이트 체크 (GitHub Releases 조회 → 새 버전 안내)
    @StateObject private var updateChecker = UpdateChecker()

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
            PopoverView(controller: controller, updateChecker: updateChecker)
                .modelContainer(modelContainer)
                .onAppear {
                    // 컨트롤러에 SwiftData 컨텍스트 연결 (최초 1회)
                    controller.attach(context: modelContainer.mainContext)
                }
                .task {
                    // 실행 시 하루 1회 새 버전 확인 (네트워크 실패는 조용히 무시)
                    await updateChecker.checkIfDue()
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
            Image(systemName: controller.menuBarSymbol)
            if controller.phase.isCountingDown {
                Text(controller.timeString)
                    .monospacedDigit()
            } else if controller.isActiveToday && controller.currentStreak > 0 {
                Text("\(controller.currentStreak)")
                    .monospacedDigit()
            }
        }
    }
}
