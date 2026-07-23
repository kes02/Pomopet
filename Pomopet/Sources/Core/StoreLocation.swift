import Foundation
import SQLite3

// MARK: - 저장소 위치 관리
// SwiftData 저장 파일의 전용 경로를 책임집니다.
//
// 배경: 샌드박스가 꺼진 앱에서 ModelContainer(for:)만 호출하면 저장 위치가
// ~/Library/Application Support/default.store 가 되는데, 이 파일은 같은 조건의
// "모든" 앱이 공유합니다. 다른 앱(예: Apple 시스템 데몬)이 자기 모델로
// 마이그레이션하는 순간 Pomopet 데이터가 통째로 사라질 수 있습니다.
// 그래서 전용 폴더(~/Library/Application Support/Pomopet/)를 쓰고,
// 과거 위치에 남아 있는 기록은 최초 1회 복사해옵니다.
enum StoreLocation {
    /// 전용 저장 파일: ~/Library/Application Support/Pomopet/Pomopet.store
    static var storeURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pomopet", isDirectory: true)
            .appendingPathComponent("Pomopet.store")
    }

    /// 전용 폴더를 만들고, 필요하면 과거 위치의 기록을 이관한 뒤 저장 URL을 돌려줍니다.
    /// 앱 시작 시 ModelContainer 생성 직전에 한 번 호출합니다.
    static func prepare() throws -> URL {
        let url = storeURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        migrateLegacyStoreIfNeeded(to: url)
        return url
    }

    // MARK: 레거시 이관

    /// 과거에 기록이 쌓였을 수 있는 위치들.
    /// - 공유 default.store: v1.2.0(샌드박스 해제) 이후 위치
    /// - 샌드박스 컨테이너: v1.1.x 이전 위치
    private static var legacyStoreURLs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let bundleID = Bundle.main.bundleIdentifier ?? "com.kes02.Pomopet"
        return [
            home.appendingPathComponent("Library/Application Support/default.store"),
            home.appendingPathComponent(
                "Library/Containers/\(bundleID)/Data/Library/Application Support/default.store"
            ),
        ]
    }

    /// 전용 store가 아직 없을 때, 레거시 위치 중 실제 기록이 가장 많은 store를 복사해옵니다.
    /// 원본은 지우지 않습니다(공유 파일은 다른 앱이 쓰고 있을 수 있음).
    private static func migrateLegacyStoreIfNeeded(to destination: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { return }

        // 이전의 실패한 이관이 남긴 부속 파일(-wal 등)이 새 store와 섞이면
        // 엉뚱한 WAL 복구가 일어날 수 있으므로 먼저 치웁니다.
        removeStoreFiles(at: destination)

        let best = legacyStoreURLs
            .map { (url: $0, records: dailyRecordCount(at: $0)) }
            .filter { $0.records > 0 }
            .max { $0.records < $1.records }
        guard let source = best?.url else { return }

        // 본파일 + -wal(아직 본파일에 반영 안 된 기록) 복사.
        // -shm은 일시 파일이라 SQLite가 재생성하므로 복사하지 않습니다.
        // 하나라도 실패하면 반쪽 복사본이 남지 않게 전부 지우고 이관을 포기합니다
        // (원본은 그대로라 수동 복구 여지는 남음).
        do {
            for suffix in ["", "-wal"] {
                let from = URL(fileURLWithPath: source.path + suffix)
                guard fm.fileExists(atPath: from.path) else { continue }
                try fm.copyItem(at: from, to: URL(fileURLWithPath: destination.path + suffix))
            }
        } catch {
            removeStoreFiles(at: destination)
        }
    }

    /// 열 수 없는(손상 등) 전용 store를 지우지 않고 .broken-<타임스탬프>로 rename해
    /// 옆으로 치워둡니다. 치운 뒤에는 자리가 비므로 빈 store로 재시도할 수 있습니다.
    static func setAsideBrokenStore() {
        let fm = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970)
        for suffix in ["", "-wal", "-shm"] {
            let from = URL(fileURLWithPath: storeURL.path + suffix)
            guard fm.fileExists(atPath: from.path) else { continue }
            try? fm.moveItem(
                at: from,
                to: URL(fileURLWithPath: storeURL.path + ".broken-\(stamp)" + suffix)
            )
        }
    }

    /// 해당 경로의 store 관련 파일(.store/-wal/-shm)을 제거합니다. 없으면 무시.
    private static func removeStoreFiles(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    /// 해당 store에 든 DailyRecord 수. Pomopet store가 아니거나 못 읽으면 -1.
    /// (다른 앱이 쓰는 파일일 수 있어 읽기 전용으로만 접근합니다.)
    private static func dailyRecordCount(at url: URL) -> Int {
        guard FileManager.default.fileExists(atPath: url.path) else { return -1 }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return -1
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM ZDAILYRECORD", -1, &stmt, nil) == SQLITE_OK else {
            return -1
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return -1 }
        return Int(sqlite3_column_int64(stmt, 0))
    }
}
