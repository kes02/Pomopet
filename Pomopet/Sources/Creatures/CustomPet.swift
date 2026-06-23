import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 색 격자 렌더링
// 임의 색을 가진 픽셀 격자([[Color?]])를 또렷한 도트로 그립니다.
// nil 칸은 투명입니다. (PixelSpriteView가 문자 격자라면, 이쪽은 색 격자용)
struct ColorGridView: View {
    let grid: [[Color?]]
    var size: CGFloat = 80

    var body: some View {
        Canvas { context, canvasSize in
            let rows = grid.count
            let cols = grid.map(\.count).max() ?? 0
            guard rows > 0, cols > 0 else { return }

            let cell = min(canvasSize.width / CGFloat(cols),
                           canvasSize.height / CGFloat(rows))
            let originX = (canvasSize.width - cell * CGFloat(cols)) / 2
            let originY = (canvasSize.height - cell * CGFloat(rows)) / 2

            for (r, row) in grid.enumerated() {
                for (c, color) in row.enumerated() {
                    guard let color else { continue }
                    let rect = CGRect(
                        x: originX + CGFloat(c) * cell,
                        y: originY + CGFloat(r) * cell,
                        width: cell + 0.6,
                        height: cell + 0.6
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Color(hex:)
// 팔레트·UI 색을 16진수로 간결하게 정의하기 위한 헬퍼.
extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

// MARK: - 커스텀 펫 저장소
// 사용자가 고른 이미지를 64x64 PNG로 줄여 영구 저장합니다(앱을 꺼도 유지).
enum CustomPetStore {
    private static let key = "pomopet.customPetImagePNG"

    static var hasImage: Bool { UserDefaults.standard.data(forKey: key) != nil }

    static func save(_ image: NSImage) {
        guard let rep = ImagePixelizer.bitmap(from: image, side: 64),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        UserDefaults.standard.set(png, forKey: key)
    }

    static func loadImage() -> NSImage? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return NSImage(data: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - 이미지 → 도트 변환
enum ImagePixelizer {
    /// 이미지를 n x n 비트맵으로 다시 그립니다(다운샘플링).
    static func bitmap(from image: NSImage, side n: Int) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }

        rep.size = NSSize(width: n, height: n)
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            ctx.imageInterpolation = .high   // 셀마다 평균색에 가깝게
            image.draw(in: NSRect(x: 0, y: 0, width: n, height: n),
                       from: .zero, operation: .copy, fraction: 1.0)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// 이미지를 resolution x resolution 색 격자로 변환합니다. 거의 투명한 칸은 nil(투명).
    static func colorGrid(from image: NSImage, resolution n: Int) -> [[Color?]] {
        guard let rep = bitmap(from: image, side: n) else { return [] }
        var grid: [[Color?]] = []
        for y in 0..<rep.pixelsHigh {
            var row: [Color?] = []
            for x in 0..<rep.pixelsWide {
                if let raw = rep.colorAt(x: x, y: y),
                   let c = raw.usingColorSpace(.deviceRGB), c.alphaComponent >= 0.25 {
                    row.append(Color(red: Double(c.redComponent),
                                     green: Double(c.greenComponent),
                                     blue: Double(c.blueComponent)))
                } else {
                    row.append(nil)
                }
            }
            grid.append(row)
        }
        return grid
    }

    /// 이미지의 대표색(불투명 픽셀 평균). 알 색·강조색에 사용.
    static func dominantColor(of image: NSImage) -> NSColor {
        guard let rep = bitmap(from: image, side: 8) else { return .systemTeal }
        var r = 0.0, g = 0.0, b = 0.0, count = 0.0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let raw = rep.colorAt(x: x, y: y),
                      let c = raw.usingColorSpace(.deviceRGB), c.alphaComponent >= 0.25 else { continue }
                r += Double(c.redComponent); g += Double(c.greenComponent); b += Double(c.blueComponent)
                count += 1
            }
        }
        guard count > 0 else { return .systemTeal }
        return NSColor(deviceRed: r / count, green: g / count, blue: b / count, alpha: 1.0)
    }
}

// MARK: - PetVisual
// 업로드한 캐릭터 이미지를 도트로 변환해 보여줍니다.
enum PetVisual {
    /// 캐릭터 도트 해상도 (고정).
    static let renderResolution = 26

    /// 현재 캐릭터의 색 격자. 캐릭터가 없으면 nil.
    static func grid() -> [[Color?]]? {
        guard let image = CustomPetStore.loadImage() else { return nil }
        return ImagePixelizer.colorGrid(from: image, resolution: renderResolution)
    }

    /// 강조색(테두리·진행바 등) = 이미지 대표색.
    static func tint() -> Color {
        guard let image = CustomPetStore.loadImage() else { return .accentColor }
        return Color(nsColor: ImagePixelizer.dominantColor(of: image))
    }
}

// MARK: - 이미지 파일 선택
// 업로드/캐릭터 변경에서 공용으로 쓰는 파일 선택기.
@MainActor
func pickImageFile() -> NSImage? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.prompt = "이 캐릭터로 시작"
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return NSImage(contentsOf: url)
}
