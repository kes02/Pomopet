import AppKit
import Vision
import CoreImage

// MARK: - 배경 지우기
//
// macOS 에 들어 있는 Vision 을 씁니다 — 미리보기 앱의 "배경 제거" 와 같은 엔진입니다.
//
// 배경 제거 오픈소스는 대부분 U²-Net 계열 딥러닝 모델이라 모델 파일만 수십~수백 MB 입니다.
// 앱 전체가 2.4MB 인데 모델이 앱보다 훨씬 커지는 셈이라 맞지 않습니다.
// Vision 은 OS 에 이미 있어서 용량이 늘지 않고, 전부 기기 안에서 돌아 네트워크도 쓰지 않습니다.

enum BackgroundRemover {

    /// 이미 배경이 정리된(투명한) 이미지인지. 이 정도 비율이면 손댈 필요가 없다고 봅니다.
    private static let alreadyCutOutRatio = 0.10

    /// 투명한 부분이 충분히 있으면 누끼 이미지로 봅니다.
    /// 이런 이미지에 배경 제거를 또 걸면 멀쩡한 부분이 깎일 수 있어 기본으로 끕니다.
    static func looksAlreadyCutOut(_ image: NSImage) -> Bool {
        guard let rep = bitmap(of: image) else { return false }

        var clear = 0, total = 0
        // 전부 훑을 필요는 없습니다 — 듬성듬성 봐도 비율은 충분히 정확합니다.
        for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
                total += 1
                if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 1) < 0.25 { clear += 1 }
            }
        }
        guard total > 0 else { return false }
        return Double(clear) / Double(total) >= alreadyCutOutRatio
    }

    /// 피사체만 남기고 배경을 투명하게 만듭니다. 피사체를 못 찾으면 nil.
    ///
    /// 원본을 그대로 두고 새 이미지를 돌려주므로, 결과가 마음에 안 들면 그냥 버리면 됩니다.
    /// 시간이 걸리는 작업이라 메인 스레드 밖에서 부릅니다.
    nonisolated static func subject(of image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg)

        do {
            try handler.perform([request])
            guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }

            // 피사체 주변 여백까지 잘라내 돌려줍니다.
            let masked = try result.generateMaskedImage(
                ofInstances: result.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )

            let ci = CIImage(cvPixelBuffer: masked)
            guard let out = CIContext().createCGImage(ci, from: ci.extent) else { return nil }
            return NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
        } catch {
            return nil
        }
    }

    private static func bitmap(of image: NSImage) -> NSBitmapImageRep? {
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }
}
