import Foundation
import CoreGraphics

struct NextMenusSettings {
    private enum Key {
        static let useZeroTopLeftInset = "useZeroTopLeftInset"
        static let showServicesInMainMenu = "showServicesInMainMenu"
        static let showHideInMainMenu = "showHideInMainMenu"
        static let showQuitInMainMenu = "showQuitInMainMenu"
        static let enableHiding = "enableHiding"
    }

    static let defaultsChangedNotification = Notification.Name("NextMenusSettingsDefaultsChanged")

    static var useZeroTopLeftInset: Bool {
        get { UserDefaults.standard.bool(forKey: Key.useZeroTopLeftInset) }
        set { set(newValue, forKey: Key.useZeroTopLeftInset) }
    }

    static var topLeftInset: CGFloat {
        useZeroTopLeftInset ? 0 : 8
    }

    static var showServicesInMainMenu: Bool {
        get { bool(forKey: Key.showServicesInMainMenu, defaultValue: true) }
        set { set(newValue, forKey: Key.showServicesInMainMenu) }
    }

    static var showHideInMainMenu: Bool {
        get { bool(forKey: Key.showHideInMainMenu, defaultValue: true) }
        set { set(newValue, forKey: Key.showHideInMainMenu) }
    }

    static var showQuitInMainMenu: Bool {
        get { bool(forKey: Key.showQuitInMainMenu, defaultValue: true) }
        set { set(newValue, forKey: Key.showQuitInMainMenu) }
    }

    static var enableHiding: Bool {
        get { bool(forKey: Key.enableHiding, defaultValue: false) }
        set { set(newValue, forKey: Key.enableHiding) }
    }

    private static func bool(forKey key: String, defaultValue: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }

    private static func set(_ value: Bool, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        NotificationCenter.default.post(name: defaultsChangedNotification, object: nil)
    }
}
