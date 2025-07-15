// WindowAccessor.swift

import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    // Optional parameter for the *content's* expected size.
    // This is used for precise centering before SwiftUI has fully laid out the content.
    var expectedContentSize: CGSize? = nil
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        
        DispatchQueue.main.async {
            guard let window = view.window else { return }

            // FIX 1: Immediately hide the window before any default rendering or repositioning occurs.
            window.alphaValue = 0.0

            // FIX 2: Apply all custom style mask and background properties *synchronously*.
            // This ensures the window is borderless and clear from its very first rendered frame.
            window.styleMask.remove(.titled)
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isMovableByWindowBackground = true
            
            // FIX 3: Calculate and apply perfect center positioning.
            if let screenFrame = NSScreen.main?.visibleFrame {
                // Use the expectedContentSize if provided, otherwise fall back to window's current size.
                // It's crucial to set the window's content size explicitly *before* setting its frame origin.
                let finalWindowSize = expectedContentSize ?? window.frame.size
                window.setContentSize(finalWindowSize)
                
                let newX = screenFrame.midX - (finalWindowSize.width / 2)
                let newY = screenFrame.midY - (finalWindowSize.height / 2)
                
                window.setFrameOrigin(NSPoint(x: newX, y: newY))
                print("[WindowAccessor] Window configured and positioned at (\(newX), \(newY)), size: \(finalWindowSize).")
            } else {
                print("[WindowAccessor] Could not get main screen frame to center window.")
            }
            
            // ✅ FIX: This is the most reliable moment to activate the application.
            // It ensures that when the window fades in, it's already the frontmost app.
            NSApp.activate(ignoringOtherApps: true)
            
            // FIX 4: Animate the window back to full visibility AFTER it's fully configured and positioned.
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2 // Short, smooth fade-in
                window.animator().alphaValue = 1.0
            })
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
