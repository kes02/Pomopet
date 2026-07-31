import SwiftUI
import AppKit

// MARK: - 캐릭터 미리보기
//
// 고른 이미지를 바로 적용하지 않고 먼저 보여줍니다.
//
// 사진이 26x26 도트로 줄고 메뉴바에서는 18pt까지 작아지는데, 그 결과는 실제로 봐야 압니다.
// 특히 배경이 흰 사진은 흰 사각형으로, 캐릭터가 작게 찍힌 사진은 알아볼 수 없게 뭉개집니다.
// 적용 전에 두 크기를 다 보여주면 "이 사진은 안 되겠다" 를 스스로 판단할 수 있습니다.

struct CharacterPreview: View {
    let image: NSImage
    let onConfirm: (NSImage) -> Void
    let onRetry: () -> Void

    @State private var removeBackground = false
    @State private var cutOut: NSImage?
    @State private var working = false
    @State private var failed = false

    /// 실제로 적용될 이미지. 배경 지우기가 켜져 있고 성공했으면 그 결과를 씁니다.
    private var shown: NSImage {
        (removeBackground ? cutOut : nil) ?? image
    }

    /// 이미지와 토글 상태를 함께 묶은 키. 둘 중 하나만 바뀌어도 다시 계산합니다.
    private var previewKey: String {
        "\(ObjectIdentifier(image).hashValue)-\(removeBackground)"
    }

    private var grid: [[Color?]] {
        let raw = ImagePixelizer.colorGrid(from: shown, resolution: PetVisual.renderResolution)
        return PetVisual.trimmed(raw) ?? raw
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("이렇게 보여요")
                .font(.system(size: 13, weight: .semibold))

            // 팝오버에서 보이는 크기
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(colors: [Color(hex: 0x121726), Color(hex: 0x1c2438)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                ColorGridView(grid: grid, size: 96)
            }
            .frame(height: 130)

            // 메뉴바에서 보이는 크기 — 여기서 알아볼 수 있는지가 사실상의 합격 기준입니다.
            HStack(spacing: 8) {
                Text("메뉴바")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let icon = PetMenuBarIcon.image(from: shown, awake: true) {
                    Image(nsImage: icon).renderingMode(.original)
                }
                if let sleeping = PetMenuBarIcon.image(from: shown, awake: false) {
                    Image(nsImage: sleeping).renderingMode(.original)
                    Text("(잠들었을 때)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))

            HStack(spacing: 6) {
                Toggle("배경 지우기", isOn: $removeBackground)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption)
                    .disabled(working)

                if working {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }

            Text(hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Button("다시 고르기", action: onRetry)
                    .buttonStyle(.bordered)

                Button {
                    onConfirm(shown)
                } label: {
                    Text("이걸로 할게요")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(working)
            }
        }
        // 이미지가 바뀌면 앞서 지운 결과를 반드시 버립니다.
        .task(id: previewKey) {
            guard removeBackground, cutOut == nil, !failed else { return }
            working = true
            let source = image
            let result = await Task.detached { BackgroundRemover.subject(of: source) }.value
            // 기다리는 동안 다른 이미지로 바뀌었으면 결과를 버립니다.
            guard source === image else { working = false; return }
            cutOut = result
            failed = (result == nil)
            working = false
        }
        .onChange(of: ObjectIdentifier(image)) { _, _ in
            cutOut = nil
            failed = false
            working = false
            removeBackground = !BackgroundRemover.looksAlreadyCutOut(image)
        }
        .onAppear {
            // 이미 누끼가 된 이미지라면 손대지 않습니다. 배경이 채워진 사진에만 기본으로 켭니다.
            removeBackground = !BackgroundRemover.looksAlreadyCutOut(image)
        }
    }

    private var hint: LocalizedStringKey {
        if working { return "배경을 지우는 중이에요…" }
        if failed { return "피사체를 찾지 못해 원본 그대로 씁니다" }
        if removeBackground { return "배경을 지웠어요. 캐릭터가 깎였으면 꺼주세요" }
        return "배경이 있는 사진은 그 배경까지 도트가 돼요"
    }
}
