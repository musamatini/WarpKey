// WindowFocusManager.swift

import SwiftUI
import AppKit

struct FocusableWindow: Identifiable, Hashable {
    static func == (lhs: FocusableWindow, rhs: FocusableWindow) -> Bool {
        return lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    let id: CGWindowID
    let appPid: pid_t
    let appName: String
    let windowTitle: String
    let axElement: AXUIElement
    let psn: ProcessSerialNumber

    func focus() {
        var psn = self.psn
        _ = _SLPSSetFrontProcessWithOptions(&psn, id, 0x200)
        makeKeyWindow(psn: &psn, wid: id)
        _ = AXUIElementPerformAction(self.axElement, kAXRaiseAction as CFString)
    }
    
    private func makeKeyWindow(psn: inout ProcessSerialNumber, wid: CGWindowID) {
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        var windowId32 = UInt32(wid)
        bytes[0x04] = 0xf8; bytes[0x3a] = 0x10
        memcpy(&bytes[0x3c], &windowId32, MemoryLayout<UInt32>.size)
        memset(&bytes[0x20], 0xff, 0x10)
        bytes[0x08] = 0x01; SLPSPostEventRecordTo(&psn, &bytes)
        bytes[0x08] = 0x02; SLPSPostEventRecordTo(&psn, &bytes)
    }
}


@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ axUiElement: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

// MARK: - WindowFocusManager (Caching Version)
struct WindowFocusManager {
    
    private static var windowCache: [FocusableWindow] = []
    private static var refreshTimer: Timer?
    private static let cacheQueue = DispatchQueue(label: "dev.warpkey.windowcache.queue", qos: .userInitiated)

    // MARK: - Public Interface
    
    static func startMonitoring() {
        stopMonitoring()
        refreshCache()
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            refreshCache()
        }
    }
    
    static func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    static func findWindow(for pid: pid_t) -> FocusableWindow? {
        return cacheQueue.sync {
            windowCache.first { $0.appPid == pid }
        }
    }
    
    // MARK: - Private Cache Management
    
    private static func refreshCache() {
        cacheQueue.async {
            let freshWindows = fetchAllWindows()
            self.windowCache = freshWindows
            print("Window cache refreshed. Found \(freshWindows.count) windows.")
        }
    }
    
    private static func fetchAllWindows() -> [FocusableWindow] {
        let axWindowCache = buildAxWindowCache()
        let cgWindowListInfo = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

        var psnCache: [pid_t: ProcessSerialNumber] = [:]
        var discoveredWindows: [FocusableWindow] = []

        for windowInfo in cgWindowListInfo {
            guard let windowLayer = windowInfo[kCGWindowLayer as String] as? Int, windowLayer == 0,
                  let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                  let appPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  let appName = windowInfo[kCGWindowOwnerName as String] as? String
            else { continue }
            
            let windowTitle = windowInfo[kCGWindowName as String] as? String
            if (windowTitle?.isEmpty ?? true) { continue }
            
            if appName == "WarpKey" { continue }

            var psn: ProcessSerialNumber
            if let cachedPSN = psnCache[appPID] {
                psn = cachedPSN
            } else if let psnValue = getPSNForPID(appPID) {
                var newPSN = ProcessSerialNumber()
                psnValue.getValue(&newPSN)
                psn = newPSN
                psnCache[appPID] = newPSN
            } else {
                continue
            }

            if let axElement = axWindowCache[windowID] {
                let focusableWindow = FocusableWindow(
                    id: windowID,
                    appPid: appPID,
                    appName: appName,
                    windowTitle: windowTitle!,
                    axElement: axElement,
                    psn: psn
                )
                discoveredWindows.append(focusableWindow)
            }
        }
        return discoveredWindows
    }
    
    private static func buildAxWindowCache() -> [CGWindowID: AXUIElement] {
        var cache: [CGWindowID: AXUIElement] = [:]
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
        }

        for app in runningApps {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            let axWindows = getAxWindows(for: axApp, pid: app.processIdentifier)
            
            for axWindow in axWindows {
                var windowId: CGWindowID = 0
                if _AXUIElementGetWindow(axWindow, &windowId) == .success, windowId != 0 {
                    cache[windowId] = axWindow
                }
            }
        }
        return cache
    }

    private static func getAxAttribute<T>(for element: AXUIElement, attribute: String) -> T? {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success {
            return value as? T
        }
        return nil
    }

    private static func getAxWindows(for axApp: AXUIElement, pid: pid_t) -> [AXUIElement] {
        var windows: [AXUIElement] = []
        
        if let axWindows: [AXUIElement] = getAxAttribute(for: axApp, attribute: kAXWindowsAttribute) {
            windows.append(contentsOf: axWindows)
        }
        
        var remoteToken = Data(count: 20)
        remoteToken.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        remoteToken.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
        remoteToken.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })

        for axUiElementId in 0..<1000 {
            var id = UInt64(axUiElementId)
            remoteToken.replaceSubrange(12..<20, with: withUnsafeBytes(of: &id) { Data($0) })
            
            if let rawElement = _AXUIElementCreateWithRemoteToken(remoteToken as CFData)?.takeRetainedValue() {
                let axUiElement = rawElement as! AXUIElement
                if let subrole: String = getAxAttribute(for: axUiElement, attribute: kAXSubroleAttribute),
                   [kAXStandardWindowSubrole, kAXDialogSubrole].contains(subrole) {
                    windows.append(axUiElement)
                }
            }
        }
        return Array(Set(windows))
    }
}
