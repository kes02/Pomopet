import SwiftUI
import AppKit

// MARK: - 물어보는 카드
//
// 화면 오른쪽 위에 잠깐 떠서 묻는 작은 카드입니다. 두 군데서 씁니다.
//  * 작업 앱을 켰을 때 — "집중 시작할까요?"
//  * 집중 중에 한참 조용할 때 — "자리 비우셨나요?"
//
// 시스템 알림(UNUserNotification) 대신 직접 만든 창을 쓰는 이유:
// 이 앱은 정식 서명이 아니라 시스템 알림이 안 뜰 수 있고, 알림 권한을 받아야 하며,
// 알림 센터에 쌓여 나중에 뒤늦게 눌리는 것도 이상합니다. 직접 띄우면 권한도 필요 없고
// 정해둔 시간 뒤 조용히 사라지게 만들 수 있습니다.

@MainActor
final class StartSuggestionPresenter {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    /// 대답 없이 저절로 사라졌을 때 알립니다.
    private var onIgnore: (() -> Void)?

    // MARK: 집중 시작 권하기

    func show(
        appName: String,
        onStart: @escaping () -> Void,
        onLater: @escaping () -> Void,
        onIgnore: @escaping () -> Void
    ) {
        present(
            visibleSeconds: 12,
            onIgnore: onIgnore,
            card: { dismiss in
                AnyView(PromptCard(
                    title: "집중 시작할까요?",
                    subtitle: "\(appName)을(를) 켰네요",
                    primary: "시작",
                    primaryIcon: "play.fill",
                    secondary: "나중에",
                    onPrimary: { onStart(); dismiss() },
                    onSecondary: { onLater(); dismiss() }
                ))
            }
        )
    }

    // MARK: 자리 비운 것 같을 때

    func showAway(
        idleMinutes: Int,
        onStop: @escaping () -> Void,
        onKeep: @escaping () -> Void,
        onIgnore: @escaping () -> Void
    ) {
        present(
            // 자리를 비운 상황이라 조금 더 오래 띄웁니다 — 돌아왔을 때 볼 수 있게.
            visibleSeconds: 30,
            onIgnore: onIgnore,
            card: { dismiss in
                AnyView(PromptCard(
                    title: "자리 비우셨나요?",
                    subtitle: "\(idleMinutes)분째 조용해요",
                    primary: "중지",
                    primaryIcon: "stop.fill",
                    secondary: "계속",
                    onPrimary: { onStop(); dismiss() },
                    onSecondary: { onKeep(); dismiss() }
                ))
            }
        )
    }

    // MARK: 공통

    private func present(
        visibleSeconds: UInt64,
        onIgnore: @escaping () -> Void,
        card: (@escaping () -> Void) -> AnyView
    ) {
        dismiss()
        self.onIgnore = onIgnore

        // 대답을 하면 무시로 세지 않습니다.
        let answered: () -> Void = { [weak self] in
            self?.onIgnore = nil
            self?.dismiss()
        }
        let content = card(answered)

        // .nonactivatingPanel 이라 이 카드가 떠도 지금 쓰던 앱의 포커스를 뺏지 않습니다.
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 108),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: content)

        position(panel)
        panel.orderFrontRegardless()
        self.panel = panel

        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: visibleSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        panel = nil

        // 대답 없이 사라진 경우에만 호출됩니다.
        onIgnore?()
        onIgnore = nil
    }

    /// 메뉴바의 펫 아이콘 아래쯤 — 오른쪽 위에 붙입니다.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = panel.frame
        let origin = NSPoint(
            x: screen.visibleFrame.maxX - frame.width - 12,
            y: screen.visibleFrame.maxY - frame.height - 8
        )
        panel.setFrameOrigin(origin)
    }
}

// MARK: - 카드 내용
struct PromptCard: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let primary: LocalizedStringKey
    let primaryIcon: String
    let secondary: LocalizedStringKey
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                CharacterView(grid: PetVisual.grid() ?? [], tint: PetVisual.tint(), active: true, size: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 6) {
                Button(action: onPrimary) {
                    Label(primary, systemImage: primaryIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(secondary, action: onSecondary)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
        )
        .frame(width: 260)
    }
}
