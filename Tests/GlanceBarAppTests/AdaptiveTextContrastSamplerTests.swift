import AppKit
import Testing
@testable import GlanceBarApp

@MainActor
@Test func wallpaperCacheReusesColorAndInvalidatesChangedInputs() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
        try? FileManager.default.removeItem(at: url)
    }
    try "first wallpaper".write(to: url, atomically: true, encoding: .utf8)
    let key = try #require(makeWallpaperCacheKey(url: url))
    var cache = WallpaperColorCache()
    var loadCount = 0

    for _ in 0..<3 {
        let color = cache.color(for: key) {
            loadCount += 1

            return .red
        }
        #expect(color == .red)
    }
    #expect(loadCount == 1)

    let changedKeys = try [
        #require(makeWallpaperCacheKey(url: url, statusItemRect: CGRect(x: 30, y: 0, width: 36, height: 24))),
        #require(makeWallpaperCacheKey(url: url, screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600))),
        #require(makeWallpaperCacheKey(url: url, backingScaleFactor: 1)),
        #require(makeWallpaperCacheKey(url: url, displayID: 2)),
        #require(makeWallpaperCacheKey(url: url, appearanceName: NSAppearance.Name.darkAqua.rawValue))
    ]

    for changedKey in changedKeys {
        #expect(changedKey != key)
        _ = cache.color(for: changedKey) {
            loadCount += 1

            return .blue
        }
    }
    #expect(loadCount == 6)

    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: url.path)
    let modifiedKey = try #require(makeWallpaperCacheKey(url: url))
    #expect(modifiedKey != key)

    try "replacement wallpaper".write(to: url, atomically: true, encoding: .utf8)
    let replacedKey = try #require(makeWallpaperCacheKey(url: url))
    #expect(replacedKey != modifiedKey)

    cache.reset()
    _ = cache.color(for: replacedKey) {
        loadCount += 1

        return .green
    }
    #expect(loadCount == 7)
}

@MainActor
@Test func wallpaperCacheRetriesFailuresAndUnverifiableFiles() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
        try? FileManager.default.removeItem(at: url)
    }
    try "wallpaper".write(to: url, atomically: true, encoding: .utf8)
    let key = try #require(makeWallpaperCacheKey(url: url))
    var cache = WallpaperColorCache()
    var loadCount = 0

    for _ in 0..<2 {
        #expect(cache.color(for: key) {
            loadCount += 1

            return nil
        } == nil)
    }
    #expect(loadCount == 2)

    for _ in 0..<2 {
        _ = cache.color(for: nil) {
            loadCount += 1

            return .red
        }
    }
    #expect(loadCount == 4)
    try FileManager.default.removeItem(at: url)
    #expect(makeWallpaperCacheKey(url: url) == nil)
}

private func makeWallpaperCacheKey(
    url: URL,
    statusItemRect: CGRect = CGRect(x: 0, y: 0, width: 36, height: 24),
    screenFrame: CGRect = CGRect(x: 0, y: 0, width: 1_000, height: 800),
    backingScaleFactor: CGFloat = 2,
    displayID: UInt32 = 1,
    appearanceName: String = NSAppearance.Name.aqua.rawValue
) -> WallpaperColorCacheKey? {
    getWallpaperColorCacheKey(
        url: url,
        statusItemRect: statusItemRect,
        screenFrame: screenFrame,
        backingScaleFactor: backingScaleFactor,
        maybeDisplayID: NSNumber(value: displayID),
        appearanceName: appearanceName
    )
}
