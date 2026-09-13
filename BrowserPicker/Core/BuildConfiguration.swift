import Foundation

enum BuildConfiguration {
    static var isDebugPreview: Bool {
        #if BROWSER_PICKER_DEBUG
        true
        #else
        false
        #endif
    }

    static var settingsDirectoryName: String {
        isDebugPreview ? "BrowserPicker Debug" : "BrowserPicker"
    }
}
