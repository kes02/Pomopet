import AppKit
import CoreImage

// MARK: - 메뉴바 펫 아이콘
//
// 메뉴바에 표정 문자 대신 실제 캐릭터를 띄웁니다.
//
// 두 가지를 신경 씁니다.
//  * 업로드한 이미지는 캐릭터 주변에 빈 공간이 많습니다. 그대로 줄이면 메뉴바에서 점처럼 보여서,
//    투명한 여백을 잘라내고 캐릭터만 키웁니다.
//  * 오늘 목표를 못 채웠으면 흑백으로 — 팝오버 안의 펫과 같은 규칙입니다.

enum PetMenuBarIcon {
    /// 메뉴바 아이콘 크기. 시스템 메뉴바 아이콘과 비슷한 크기.
    static let size: CGFloat = 18

    private static var cache: [Bool: NSImage] = [:]

    /// 캐릭터를 바꾸면 다시 그려야 합니다.
    static func invalidate() {
        cache.removeAll()
    }

    static func image(awake: Bool) -> NSImage? {
        if let hit = cache[awake] { return hit }
        guard let rendered = render(awake: awake) else { return nil }
        cache[awake] = rendered
        return rendered
    }

    // MARK: 그리기

    /// 저장 전 이미지로도 만들 수 있게 — 업로드 미리보기에서 씁니다.
    static func image(from source: NSImage, awake: Bool) -> NSImage? {
        render(source: source, awake: awake)
    }

    private static func render(awake: Bool) -> NSImage? {
        guard let source = CustomPetStore.loadImage() else { return nil }
        return render(source: source, awake: awake)
    }

    private static func render(source: NSImage, awake: Bool) -> NSImage? {
        guard let crop = opaqueBounds(of: source) else { return nil }

        let canvas = NSImage(size: NSSize(width: size, height: size))
        canvas.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        // 캐릭터가 정사각형이 아닐 수 있으니 비율을 지켜 맞춥니다. 사방에 1pt 여백을 둡니다.
        let inset: CGFloat = 1
        let available = size - inset * 2
        let scale = min(available / crop.width, available / crop.height)
        let drawn = NSSize(width: crop.width * scale, height: crop.height * scale)
        let target = NSRect(
            x: (size - drawn.width) / 2,
            y: (size - drawn.height) / 2,
            width: drawn.width,
            height: drawn.height
        )
        source.draw(in: target, from: crop, operation: .sourceOver, fraction: 1.0)
        canvas.unlockFocus()

        let result = awake ? canvas : grayscale(canvas) ?? canvas
        // 템플릿으로 두면 macOS 가 단색 실루엣으로 칠해버립니다 — 캐릭터 색을 살리려면 꺼야 합니다.
        result.isTemplate = false
        return result
    }

    /// 여백을 찾을 때 훑는 비트맵 한 변(px).
    private static let scanSide = 64

    /// 불투명한 칸이 차지하는 사각형(비트맵 픽셀 좌표, 위에서 아래로).
    private typealias PixelBox = (minX: Int, maxX: Int, minY: Int, maxY: Int)

    /// 실제로 그림이 있는 영역(투명하지 않은 부분)을 이미지 좌표계로 돌려줍니다.
    private static func opaqueBounds(of image: NSImage) -> NSRect? {
        guard image.size.width > 0, image.size.height > 0,
              let rep = ImagePixelizer.bitmap(from: image, side: scanSide),
              let box = opaquePixelBox(in: rep)
        else { return nil }

        return imageRect(of: box, in: image.size)
    }

    /// 비트맵을 훑어 불투명한 칸이 차지하는 범위를 찾습니다. 전부 투명하면 nil.
    private static func opaquePixelBox(in rep: NSBitmapImageRep) -> PixelBox? {
        var minX = scanSide, maxX = -1, minY = scanSide, maxY = -1
        for y in 0..<scanSide {
            for x in 0..<scanSide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent >= 0.25 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return (minX, maxX, minY, maxY)
    }

    /// 비트맵 픽셀 좌표를 원본 이미지 좌표로 되돌립니다.
    ///
    /// 비트맵은 원본을 비율 그대로 정사각형 안에 넣고 남는 자리를 비워둔 것입니다.
    /// 그래서 되돌릴 때는 그 빈 자리(위아래 또는 좌우 여백)를 먼저 빼야 합니다.
    /// 가로 비율만으로 환산하면 정사각형이 아닌 사진에서 세로 위치가 통째로 밀려,
    /// 미리보기에 캐릭터의 절반만 나옵니다.
    private static func imageRect(of box: PixelBox, in imageSize: NSSize) -> NSRect {
        let side = CGFloat(scanSide)
        let fit = min(side / imageSize.width, side / imageSize.height)
        let insetX = (side - imageSize.width * fit) / 2
        let insetY = (side - imageSize.height * fit) / 2

        // 비트맵은 위에서 아래로(y 증가), NSImage 는 아래에서 위로 좌표를 셉니다. 뒤집어 줍니다.
        let bottomUpY = CGFloat(scanSide - 1 - box.maxY)

        return NSRect(
            x: (CGFloat(box.minX) - insetX) / fit,
            y: (bottomUpY - insetY) / fit,
            width: CGFloat(box.maxX - box.minX + 1) / fit,
            height: CGFloat(box.maxY - box.minY + 1) / fit
        )
    }

    /// 잠든 상태 — 채도를 0으로.
    private static func grayscale(_ image: NSImage) -> NSImage? {
        guard let tiff = image.tiffRepresentation,
              let input = CIImage(data: tiff),
              let filter = CIFilter(name: "CIColorControls")
        else { return nil }

        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)
        filter.setValue(-0.1, forKey: kCIInputBrightnessKey)
        guard let output = filter.outputImage else { return nil }

        let rep = NSCIImageRep(ciImage: output)
        let result = NSImage(size: image.size)
        result.addRepresentation(rep)
        return result
    }
}
