import SwiftUI
import SwiftData

// MARK: - PomopetApp
// 앱의 진입점. macOS 메뉴바에만 존재하는 앱입니다 (Dock 아이콘 없음).
@main
struct PomopetApp: App {
    // 앱 전역에서 공유되는 컨트롤러
    @StateObject private var controller: PomopetController

    // Sparkle 자동 업데이트
    @StateObject private var updater = UpdaterManager()

    // 앱 내 언어 전환 (시스템 언어와 무관하게 ko/en)
    @StateObject private var lang = LanguageManager()

    // 친구 연동 (기본 꺼짐 — 켜기 전에는 네트워크를 쓰지 않음)
    @StateObject private var friends: FriendStore

    // 작업 앱을 켜면 집중 시작을 권하는 기능 (기본 꺼짐)
    @StateObject private var workWatcher: WorkAppWatcher
    private let suggestion = StartSuggestionPresenter()

    // 집중 중에 한참 조용하면 중지할지 물어봅니다 (자리 비운 시간이 기록에 섞이지 않도록)
    private let idleWatcher = IdleWatcher()

    // SwiftData 저장소 컨테이너
    let modelContainer: ModelContainer

    init() {
        do {
            // 전용 경로 필수: 기본 위치(공유 default.store)는 다른 앱이 덮어쓸 수 있음
            let storeURL = try StoreLocation.prepare()
            let config = ModelConfiguration(url: storeURL)
            do {
                modelContainer = try ModelContainer(
                    for: DailyRecord.self, AppStats.self,
                    configurations: config
                )
            } catch {
                // store 손상 시 매 실행 크래시로 이어지지 않게: 손상 파일을
                // .broken-*으로 치워두고(수동 복구용) 빈 store로 1회 재시도
                StoreLocation.setAsideBrokenStore()
                modelContainer = try ModelContainer(
                    for: DailyRecord.self, AppStats.self,
                    configurations: config
                )
            }
        } catch {
            fatalError("SwiftData 컨테이너 생성 실패: \(error)")
        }

        // 팝오버가 아니라 여기서 조립합니다.
        // MenuBarExtra(.window)의 내용은 사용자가 메뉴바를 클릭해야 만들어지는데,
        // 작업 시작 제안은 팝오버를 한 번도 열지 않아도 동작해야 합니다.
        // (SwiftData 연결이 안 된 채로 세션이 시작되면 그 세션이 기록되지 않습니다)
        let controller = PomopetController()
        controller.attach(context: modelContainer.mainContext)
        _controller = StateObject(wrappedValue: controller)

        let friends = FriendStore()
        friends.controller = controller
        controller.onProgressChanged = { [weak friends] in
            Task { @MainActor in await friends?.sync() }
        }
        friends.startSyncing()
        _friends = StateObject(wrappedValue: friends)

        let watcher = WorkAppWatcher()
        watcher.controller = controller
        _workWatcher = StateObject(wrappedValue: watcher)

        let presenter = suggestion
        watcher.onSuggest = { [weak controller, weak watcher] appName in
            presenter.show(
                appName: appName,
                onStart: {
                    watcher?.noteAccepted()
                    controller?.startFocus()
                },
                onLater: { watcher?.snooze() },
                // 대답 없이 사라진 것도 한 번의 거절로 칩니다 — 아니면 무시할수록 더 자주 뜹니다.
                onIgnore: { watcher?.noteIgnored() }
            )
        }
        watcher.start()

        // 자리를 비운 것 같으면 물어봅니다.
        // 대답이 없으면 중지합니다 — 대답이 없다는 건 아직 자리에 없다는 뜻이라,
        // 그대로 두면 안 한 시간이 그대로 기록됩니다.
        idleWatcher.controller = controller
        idleWatcher.onAway = { [weak controller, weak watcher] minutes in
            presenter.showAway(
                idleMinutes: minutes,
                onStop: { controller?.stop() },
                onKeep: { },
                onIgnore: {
                    controller?.stop()
                    watcher?.snooze()   // 자리에 없으니 시작 제안도 잠시 멈춥니다
                }
            )
        }
        idleWatcher.start()
    }

    var body: some Scene {
        // MenuBarExtra: 메뉴바에 아이콘을 띄우는 macOS 13+ API
        MenuBarExtra {
            PopoverView(controller: controller, updater: updater, lang: lang,
                        friends: friends, workWatcher: workWatcher)
                .environment(\.locale, lang.locale)   // 선택 언어로 포맷/번역 갱신
                .modelContainer(modelContainer)
        } label: {
            // 메뉴바에 표시되는 라벨: 공부 상태(활성/잠듦) 심볼 + 연속일
            MenuBarLabel(controller: controller, friends: friends)
        }
        .menuBarExtraStyle(.window) // 팝오버 형태 (.menu가 아닌 커스텀 뷰)
    }
}

// MARK: - MenuBarLabel
//
// 메뉴바에 실제로 보이는 부분 — 업로드한 캐릭터를 그대로 띄웁니다.
// 오늘 목표를 채웠으면 컬러, 못 채웠으면 흑백으로 잠들어 있습니다.
// 집중 중에는 옆에 남은 시간이, 그 외에는 연속일이 붙습니다.
struct MenuBarLabel: View {
    @ObservedObject var controller: PomopetController
    @ObservedObject var friends: FriendStore

    var body: some View {
        HStack(spacing: 3) {
            petIcon

            if controller.phase.isCountingDown {
                Text(controller.timeString)
                    .monospacedDigit()
            } else if controller.isActiveToday && controller.currentStreak > 0 {
                Text("\(controller.currentStreak)")
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var petIcon: some View {
        // 집중 중에는 자고 있어도 깨어난 모습으로 — 지금 공부하고 있다는 표시.
        let awake = controller.isActiveToday || controller.phase == .focusing

        if let icon = PetMenuBarIcon.image(awake: awake) {
            Image(nsImage: icon)
                .renderingMode(.original)
        } else if friends.incomingNudge != nil {
            // 친구가 깨웠는데 아직 캐릭터가 없는 경우
            Text(verbatim: "(°ロ°)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        } else {
            // 아직 캐릭터를 안 올린 상태
            Text(verbatim: "(·_·)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }
}
