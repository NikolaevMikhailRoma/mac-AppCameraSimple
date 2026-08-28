import XCTest
@testable import AppCameraSimpleCore

final class FilenamesTests: XCTestCase {
    private func date(_ string: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: string)!
    }

    func testTimestampFormat() {
        XCTAssertEqual(Filenames.timestamp(for: date("2026-08-28 15:01:02")), "20260828_150102")
    }

    func testCaptureNameAppendsExtension() {
        XCTAssertEqual(
            Filenames.captureName(ext: "jpg", date: date("2026-01-05 09:07:03")),
            "20260105_090703.jpg"
        )
    }
}

final class MovieFormatTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "MovieFormatTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func testRawStringRoundTrip() {
        XCTAssertEqual(MovieFormat(rawValue: "mov"), .mov)
        XCTAssertEqual(MovieFormat(rawValue: "mp4"), .mp4)
        XCTAssertEqual(MovieFormat.mov.rawValue, "mov")
        XCTAssertEqual(MovieFormat.mp4.rawValue, "mp4")
    }

    func testFileExtensionMapping() {
        XCTAssertEqual(MovieFormat.mov.fileExtension, "mov")
        XCTAssertEqual(MovieFormat.mp4.fileExtension, "mp4")
    }

    func testDefaultsToMP4WhenNothingStored() {
        XCTAssertEqual(MovieFormat.stored(in: makeDefaults()), .mp4)
    }

    func testDefaultsToMP4OnUnrecognizedValue() {
        let d = makeDefaults()
        d.set("avi", forKey: MovieFormat.storageKey)
        XCTAssertEqual(MovieFormat.stored(in: d), .mp4)
    }

    func testStoredValueIsRead() {
        let d = makeDefaults()
        d.set("mov", forKey: MovieFormat.storageKey)
        XCTAssertEqual(MovieFormat.stored(in: d), .mov)
    }
}

final class ElapsedTimeTests: XCTestCase {
    func testUnderOneMinute() {
        XCTAssertEqual(ElapsedTime.string(from: 5), "00:05")
    }

    func testMinutesAndSeconds() {
        XCTAssertEqual(ElapsedTime.string(from: 65), "01:05")
        XCTAssertEqual(ElapsedTime.string(from: 599), "09:59")
    }

    func testHours() {
        XCTAssertEqual(ElapsedTime.string(from: 3661), "1:01:01")
    }

    func testNegativeClampsToZero() {
        XCTAssertEqual(ElapsedTime.string(from: -10), "00:00")
    }

    func testTruncatesFractionalSeconds() {
        XCTAssertEqual(ElapsedTime.string(from: 12.9), "00:12")
    }
}

final class RunningClockTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testAccumulatesOnlyRunningTime() {
        var clock = RunningClock()
        clock.start(now: at(0))
        clock.pause(now: at(10))      // 10s recorded
        clock.start(now: at(30))      // 20s paused, not counted
        XCTAssertEqual(clock.elapsed(now: at(45)), 25, accuracy: 0.0001)
    }

    func testElapsedFrozenWhilePaused() {
        var clock = RunningClock()
        clock.start(now: at(0))
        clock.pause(now: at(7))
        XCTAssertEqual(clock.elapsed(now: at(100)), 7, accuracy: 0.0001)
        XCTAssertFalse(clock.isRunning)
    }

    func testStartIsIdempotentWhileRunning() {
        var clock = RunningClock()
        clock.start(now: at(0))
        clock.start(now: at(5))       // ignored
        XCTAssertEqual(clock.elapsed(now: at(10)), 10, accuracy: 0.0001)
    }

    func testResetClearsEverything() {
        var clock = RunningClock()
        clock.start(now: at(0))
        clock.pause(now: at(10))
        clock.reset()
        XCTAssertEqual(clock.elapsed(now: at(20)), 0, accuracy: 0.0001)
    }
}

final class SaveFolderStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "SaveFolderStoreTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func makeTempDir() throws -> URL {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AppCameraSimpleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func store(_ defaults: UserDefaults, _ prefix: String, _ defaultFolder: URL) -> SaveFolderStore {
        SaveFolderStore(defaults: defaults, keyPrefix: prefix, defaultFolder: defaultFolder, securityScoped: false)
    }

    func testDefaultFolderUsedWhenNothingStored() {
        let def = SaveFolderStore.picturesSubfolder(appName: "AppCameraSimple")
        let s = store(makeDefaults(), "Photo", def)
        XCTAssertEqual(s.resolvedFolder().standardizedFileURL, def.standardizedFileURL)
    }

    func testSetFolderPersistsAndResolves() throws {
        let defaults = makeDefaults()
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let def = SaveFolderStore.picturesSubfolder(appName: "X")

        store(defaults, "Photo", def).setFolder(tmp)

        // A fresh instance (as after relaunch) must resolve the same folder.
        let reloaded = store(defaults, "Photo", def)
        XCTAssertEqual(reloaded.resolvedFolder().standardizedFileURL, tmp.standardizedFileURL)
    }

    func testTwoStoresPersistAndResolveIndependently() throws {
        let defaults = makeDefaults()
        let photoTmp = try makeTempDir()
        let videoTmp = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: photoTmp)
            try? FileManager.default.removeItem(at: videoTmp)
        }
        let photoDefault = SaveFolderStore.picturesSubfolder(appName: "P")
        let videoDefault = URL(fileURLWithPath: "/tmp/video-default", isDirectory: true)

        store(defaults, "Photo", photoDefault).setFolder(photoTmp)
        store(defaults, "Video", videoDefault).setFolder(videoTmp)

        XCTAssertEqual(store(defaults, "Photo", photoDefault).resolvedFolder().standardizedFileURL,
                       photoTmp.standardizedFileURL)
        XCTAssertEqual(store(defaults, "Video", videoDefault).resolvedFolder().standardizedFileURL,
                       videoTmp.standardizedFileURL)
    }

    func testDefaultsArePerInstance() {
        let defaults = makeDefaults()
        let photoDefault = SaveFolderStore.picturesSubfolder(appName: "AppCameraSimple")
        let videoDefault = URL(fileURLWithPath: "/tmp/only-video", isDirectory: true)
        // Only the photo store gets a folder set.
        let photoTmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        store(defaults, "Photo", photoDefault).setFolder(photoTmp)

        XCTAssertEqual(store(defaults, "Video", videoDefault).resolvedFolder().standardizedFileURL,
                       videoDefault.standardizedFileURL)
    }

    func testBookmarkRoundTrip() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AppCameraSimpleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let resolved = try XCTUnwrap(SaveFolderStore.bookmarkRoundTrip(tmp))
        XCTAssertEqual(resolved.standardizedFileURL, tmp.standardizedFileURL)
    }
}
