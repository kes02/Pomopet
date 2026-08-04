import SwiftUI
import AppKit

// MARK: - NudgeBanner
// 친구가 나를 찔렀을 때 팝오버 위쪽에 잠깐 뜨는 줄.
struct NudgeBanner: View {
    let nudge: NudgeEvent
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: "🫵")
            Text("\(nudge.displayName)님이 깨웠어요")
                .font(.caption)
                .fontWeight(.medium)
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark").font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.18))
        )
    }
}
