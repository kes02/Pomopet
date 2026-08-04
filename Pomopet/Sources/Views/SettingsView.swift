import SwiftUI
import AppKit

// MARK: - SettingsView
// 타이머 길이 + 일일 목표 + 캐릭터 변경.
struct SettingsView: View {
    @ObservedObject var controller: PomopetController
    @ObservedObject var updater: UpdaterManager
    @ObservedObject var lang: LanguageManager
    @ObservedObject var workWatcher: WorkAppWatcher
    @State private var focus: Double
    @State private var breakV: Double
    @State private var didSave = false
    @State private var saveMessageToken = 0
    @State private var confirmingAppRemoval: String?   // 지울지 물어보는 중인 앱의 bundleID
    @State private var pendingCharacter: NSImage?      // 미리보기 중인 새 캐릭터

    init(controller: PomopetController, updater: UpdaterManager, lang: LanguageManager,
         workWatcher: WorkAppWatcher) {
        self.controller = controller
        self.updater = updater
        self.lang = lang
        self.workWatcher = workWatcher
        _focus = State(initialValue: Double(controller.settings.focusMinutes))
        _breakV = State(initialValue: Double(controller.settings.breakMinutes))
    }

    var body: some View {
        // 항목마다 제목과 구분선을 둡니다.
        // 예전에는 "캐릭터 바꾸기" 와 "저장" 이 같은 줄에 나란히 있어서,
        // 저장이 무엇을 저장하는 건지(캐릭터인지 타이머인지) 알기 어려웠습니다.
        VStack(spacing: 14) {
            timerSection

            Divider()

            characterSection

            Divider()

            autoStartRow

            Divider()

            languageRow

            Divider()

            updateRow

            Button("Pomopet 종료") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
    }

    // 타이머 길이 — 이 항목의 저장 버튼은 위 두 슬라이더만 저장합니다.
    private var timerSection: some View {
        VStack(spacing: 8) {
            sectionTitle("타이머")

            sliderRow(title: "집중", value: $focus, range: 5...60, unit: "분")
            sliderRow(title: "휴식", value: $breakV, range: 1...30, unit: "분")

            HStack {
                Label("저장되었습니다", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .opacity(didSave ? 1 : 0)
                    .animation(.easeInOut(duration: didSave ? 0.15 : 0.5), value: didSave)

                Spacer()

                Button("타이머 저장") {
                    var s = controller.settings
                    s.focusMinutes = Int(focus)
                    s.breakMinutes = Int(breakV)
                    controller.updateSettings(s)
                    showSavedMessage()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!timerChanged)
            }
        }
        // 값을 수정하면 저장 메시지를 숨겨 현재 상태를 반영
        .onChange(of: focus) { didSave = false }
        .onChange(of: breakV) { didSave = false }
    }

    /// 슬라이더를 건드리지 않았으면 저장할 게 없습니다.
    private var timerChanged: Bool {
        Int(focus) != controller.settings.focusMinutes || Int(breakV) != controller.settings.breakMinutes
    }

    // 캐릭터 — 고르는 즉시 바뀌므로 따로 저장할 게 없습니다.
    @ViewBuilder
    private var characterSection: some View {
        VStack(spacing: 6) {
            sectionTitle("캐릭터")

            if let pending = pendingCharacter {
                CharacterPreview(
                    image: pending,
                    onConfirm: { final in
                        controller.changeCharacter(final)
                        pendingCharacter = nil
                    },
                    onRetry: { pendingCharacter = pickImageFile() ?? pending }
                )
                // 다른 이미지를 고르면 미리보기를 새로 시작합니다.
                .id(ObjectIdentifier(pending))
            } else {
                Button {
                    pendingCharacter = pickImageFile()
                } label: {
                    Label("캐릭터 바꾸기", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Text("바꿔도 연속 기록과 집중 시간은 그대로예요")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 항목 제목.
    private func sectionTitle(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 작업 앱을 켜면 집중을 시작해주는 기능.
    private var autoStartRow: some View {
        VStack(spacing: 6) {
            sectionTitle("작업 시작")

            Toggle(isOn: Binding(
                get: { workWatcher.settings.enabled },
                set: { workWatcher.settings.enabled = $0 }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("작업 시작하면 자동으로").font(.callout)
                    Text("정해둔 앱을 켜면 \(workWatcher.settings.countdownSeconds)초 뒤 집중이 시작돼요")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            if workWatcher.settings.enabled {
                VStack(spacing: Self.appRowSpacing) {
                    // 4개까지는 그대로 다 보이고, 그보다 많으면 스크롤됩니다.
                    // 높이를 줄 수에 딱 맞추지 않고 한 줄이 반쯤 걸치게 두어,
                    // 아래에 더 있다는 걸 잘린 모습으로 알 수 있게 합니다.
                    if workWatcher.settings.apps.count > Self.appRowsWithoutScroll {
                        ScrollView { appRows }
                            .frame(height: Self.appListHeight)
                    } else {
                        appRows
                    }

                    Button {
                        if let picked = pickApplication(),
                           !workWatcher.settings.apps.contains(where: { $0.bundleID == picked.bundleID }) {
                            workWatcher.settings.apps.append(picked)
                        }
                    } label: {
                        Label("작업 앱 추가", systemImage: "plus")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if workWatcher.settings.apps.isEmpty {
                        Text("Xcode, VS Code처럼 작업할 때 켜는 앱을 골라주세요")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// 스크롤 없이 다 보여줄 작업 앱 수.
    private static let appRowsWithoutScroll = 4
    /// 한 줄 높이(아이콘 14 + 위아래 여백)와 줄 사이 간격.
    private static let appRowHeight: CGFloat = 20
    private static let appRowSpacing: CGFloat = 4
    /// 네 줄 반이 보이는 높이. 다섯 번째가 반쯤 잘려 더 있다는 게 드러납니다.
    private static let appListHeight: CGFloat = appRowHeight * 4.5 + appRowSpacing * 4

    private var appRows: some View {
        VStack(spacing: Self.appRowSpacing) {
            ForEach(workWatcher.settings.apps) { app in
                HStack(spacing: 6) {
                    if let icon = app.icon {
                        Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                    }
                    Text(verbatim: app.name).font(.caption).lineLimit(1)

                    Spacer()

                    if confirmingAppRemoval == app.bundleID {
                        Text("뺄까요?")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Button("빼기") {
                            workWatcher.settings.apps.removeAll { $0.bundleID == app.bundleID }
                            confirmingAppRemoval = nil
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                        .tint(.red)
                        Button {
                            confirmingAppRemoval = nil
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 8))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    } else {
                        Button {
                            confirmingAppRemoval = app.bundleID
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 8))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(height: Self.appRowHeight)
            }
        }
    }

    // 친구 연동을 켠 뒤의 관리 항목 — 코드 재발급과 연동 끄기.
    // 언어 전환: 시스템 언어와 무관하게 한국어/영어를 버튼으로 직접 선택.
    private var languageRow: some View {
        HStack {
            Text("언어").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            langButton("한국어", "ko")
            langButton("English", "en")
        }
    }

    // 언어 버튼 — 선택된 쪽은 강조(accent), 나머지는 흐리게. 라벨은 각 언어 고유명이라 verbatim.
    private func langButton(_ title: String, _ code: String) -> some View {
        let active = lang.code == code
        return Button { lang.select(code) } label: {
            Text(verbatim: title)
                .font(.caption2)
                .frame(minWidth: 46)
        }
        .buttonStyle(.borderedProminent)
        .tint(active ? .accentColor : Color.gray.opacity(0.35))
        .controlSize(.small)
    }

    // 버전 표시 + Sparkle 업데이트 확인. 버튼을 누르면 Sparkle이 자체 창(버전·릴리스노트·설치+재시작)을 띄움.
    private var updateRow: some View {
        VStack(spacing: 6) {
            HStack {
                Text("버전").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("v\(appVersion)").font(.caption).foregroundStyle(.secondary)
            }

            Button {
                updater.checkForUpdates()
            } label: {
                Label("업데이트 확인", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!updater.canCheckForUpdates)
        }
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }

    /// 저장 직후 "저장되었습니다" 를 잠깐 띄웠다가 스스로 사라지게 합니다.
    /// 저장 버튼은 값을 다시 건드리기 전까지 비활성이라, 이 메시지가 유일한 확인 신호입니다.
    private func showSavedMessage() {
        saveMessageToken += 1
        let token = saveMessageToken
        didSave = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            // 그사이 다시 저장했으면 새 타이머에 맡기고 여기서는 끄지 않습니다.
            if token == saveMessageToken { didSave = false }
        }
    }

    private func sliderRow(title: LocalizedStringKey, value: Binding<Double>,
                           range: ClosedRange<Double>, unit: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                (Text("\(Int(value.wrappedValue))") + Text(unit))
                    .font(.callout).fontWeight(.semibold)
            }
            Slider(value: value, in: range, step: 1)
        }
    }
}
