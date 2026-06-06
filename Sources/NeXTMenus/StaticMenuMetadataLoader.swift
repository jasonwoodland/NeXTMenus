import Cocoa
#if SWIFT_PACKAGE
import NeXTMenusKit
#endif

enum StaticMenuMetadataLoader {
    private static var metadataCache = [String: [StaticMenuItemMetadata]]()
    private static var failedCacheKeys = Set<String>()
    private static let cacheLock = NSLock()

    static func metadataItems(for app: NSRunningApplication?) -> [StaticMenuItemMetadata] {
        guard let app,
              let bundleURL = app.bundleURL,
              let bundle = Bundle(url: bundleURL) else {
            return []
        }

        let key = cacheKey(for: bundle, bundleURL: bundleURL)
        cacheLock.lock()
        if let cached = metadataCache[key] {
            cacheLock.unlock()
            return cached
        }
        if failedCacheKeys.contains(key) {
            cacheLock.unlock()
            return []
        }
        cacheLock.unlock()

        // NSNib / NSMenu are AppKit objects. Populate the cache only on the
        // main thread; background extraction paths can safely use already
        // cached value metadata or no-op on a cache miss.
        guard Thread.isMainThread else { return [] }

        guard let loaded = loadMetadataItems(from: bundle) else {
            cacheLock.lock()
            failedCacheKeys.insert(key)
            cacheLock.unlock()
            return []
        }

        cacheLock.lock()
        metadataCache[key] = loaded
        cacheLock.unlock()
        return loaded
    }

    static func metadataItems(from menu: NSMenu) -> [StaticMenuItemMetadata] {
        menu.items.map { item in
            StaticMenuItemMetadata(
                identifier: item.identifier?.rawValue,
                title: item.title,
                submenuItems: item.submenu.map { metadataItems(from: $0) } ?? []
            )
        }
    }

    private static func loadMetadataItems(from bundle: Bundle) -> [StaticMenuItemMetadata]? {
        precondition(Thread.isMainThread)

        for nibName in mainMenuNibNames(for: bundle) {
            guard let nib = NSNib(nibNamed: NSNib.Name(nibName), bundle: bundle) else { continue }

            var topLevelObjects: NSArray?
            guard nib.instantiate(withOwner: nil, topLevelObjects: &topLevelObjects) else { continue }
            let menus = (topLevelObjects as? [Any])?.compactMap { $0 as? NSMenu } ?? []
            guard !menus.isEmpty else { continue }

            let metadata = menus.flatMap { metadataItems(from: $0) }
            guard !metadata.isEmpty else { continue }
            return metadata
        }

        return nil
    }

    private static func mainMenuNibNames(for bundle: Bundle) -> [String] {
        var names = [String]()
        if let mainNibName = bundle.object(forInfoDictionaryKey: "NSMainNibFile") as? String,
           !mainNibName.isEmpty {
            names.append(mainNibName)
        }
        names.append("MainMenu")

        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    private static func cacheKey(for bundle: Bundle, bundleURL: URL) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let mainNibName = bundle.object(forInfoDictionaryKey: "NSMainNibFile") as? String ?? "MainMenu"
        return "\(bundleURL.path)|\(version)|\(mainNibName)"
    }
}
