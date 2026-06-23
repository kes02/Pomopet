// Pomopet 앱 아이콘 생성기 — 외부 이미지 없이 코드로 렌더링.
//
// 디자인: 따뜻한 라운드 스퀘어 배경 위에, 깨어난(•ᴗ•) 픽셀 펫 캐릭터 + ❤️.
//   핵심 메시지 = "내 펫이 깨어난다" (포모도로가 아니라 '재우지 않기'가 컨셉).
//
// 1024 마스터 생성 후 sips로 전 사이즈를 AppIcon.appiconset에 채우는 전체 레시피:
//
//   swift scripts/gen-icon.swift /tmp/icon_1024.png
//   ICONSET=Pomopet/Assets.xcassets/AppIcon.appiconset
//   for pair in "16:icon_16" "32:icon_16@2x" "32:icon_32" "64:icon_32@2x" \
//               "128:icon_128" "256:icon_128@2x" "256:icon_256" "512:icon_256@2x" "512:icon_512"; do
//     sips -z "${pair%%:*}" "${pair%%:*}" /tmp/icon_1024.png --out "$ICONSET/${pair##*:}.png"
//   done
//   cp /tmp/icon_1024.png "$ICONSET/icon_512@2x.png"
//
import AppKit
import Foundation

let SIZE = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: SIZE, pixelsHigh: SIZE,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
let cg = ctx.cgContext

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255.0,
            green: CGFloat((hex >> 8) & 0xff) / 255.0,
            blue: CGFloat(hex & 0xff) / 255.0, alpha: 1)
}

let S = CGFloat(SIZE)

// 1) 배경: 라운드 스퀘어(macOS 스퀘어클) + 따뜻한 그라데이션
let bgRect = NSRect(x: 0, y: 0, width: S, height: S)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: S * 0.2237, yRadius: S * 0.2237)
bgPath.addClip()
NSGradient(colors: [color(0xFFE0B5), color(0xFFF4E2)])!.draw(in: bgRect, angle: 90) // 아래(peach)→위(cream)

// 2) 픽셀 펫 캐릭터(깨어남) + 하트
let G = 18
let bcx = 8.5, bcy = 9.5, bar = 5.3, bbr = 6.3 // 몸통(둥근 알 모양)

let earL: Set<[Int]>      = [[5,3],[6,3],[5,4],[6,4],[6,2]]
let earR: Set<[Int]>      = [[11,3],[12,3],[11,4],[12,4],[11,2]]
let earIn: Set<[Int]>     = [[6,3],[11,3]]
let feet: Set<[Int]>      = [[6,16],[7,16],[10,16],[11,16]]
let feetShade: Set<[Int]> = [[6,16],[11,16]]
let eyes: Set<[Int]>      = [[6,8],[11,8]]
let cheeks: Set<[Int]>    = [[5,9],[12,9]]
let mouth: Set<[Int]>     = [[7,10],[8,11],[9,11],[10,10]]            // ᴗ 모양 미소
let heart: Set<[Int]>     = [[14,1],[16,1],[13,2],[14,2],[15,2],[16,2],[17,2],[14,3],[15,3],[16,3],[15,4]]
let heartDark: Set<[Int]> = [[13,2],[17,2]]

func cellColor(_ x: Int, _ y: Int) -> NSColor? {
    let key = [x, y]
    if heart.contains(key) { return heartDark.contains(key) ? color(0xC9281C) : color(0xF0473A) }
    if earL.contains(key) || earR.contains(key) { return earIn.contains(key) ? color(0xB5651E) : color(0xF2A24E) }
    if feet.contains(key) { return feetShade.contains(key) ? color(0xCE7A2E) : color(0xF2A24E) }
    let dx = Double(x) - bcx, dy = Double(y) - bcy
    let r2 = (dx * dx) / (bar * bar) + (dy * dy) / (bbr * bbr)
    guard r2 <= 1.0 else { return nil }
    if eyes.contains(key) || mouth.contains(key) { return color(0x3A2A22) }
    if cheeks.contains(key) { return color(0xFF8F6B) }
    if r2 > 0.60 && (dx + dy) > 1.3 { return color(0xCE7A2E) }        // 우하단 그림자
    if r2 > 0.40 && dx < -0.6 && dy < -0.6 { return color(0xFFC880) } // 좌상단 하이라이트
    return color(0xF2A24E)                                            // 몸체(앰버)
}

cg.setShouldAntialias(false)
let art = S * 0.60
let cell = art / CGFloat(G)
let originX = (S - art) / 2
let originY = (S - art) / 2
for y in 0..<G {
    for x in 0..<G {
        guard let c = cellColor(x, y) else { continue }
        c.setFill()
        let rx = originX + CGFloat(x) * cell - 0.5
        let ry = originY + CGFloat(G - 1 - y) * cell - 0.5 // y: 위(0)→아래 기준이라 뒤집음
        NSRect(x: rx, y: ry, width: cell + 1, height: cell + 1).fill()
    }
}

NSGraphicsContext.restoreGraphicsState()

// 3) PNG 저장
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("PNG 인코딩 실패\n".data(using: .utf8)!); exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("✅ 저장: \(outPath)")
