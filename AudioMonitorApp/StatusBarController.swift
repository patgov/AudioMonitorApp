    // Created by Pat Govan on 4/1/25.

import SwiftUI

#if os(macOS)
import AppKit
#endif

#if os(macOS)
class StatusBarController {
    private var statusItem: NSStatusItem!
    private var popover = NSPopover()
    
    init(popoverContent: some View) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Audio Stats")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        popover.contentSize = NSSize(width: 260, height: 180)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: popoverContent)
    }
    
    @objc private func togglePopover() {
        DispatchQueue.main.async {
            guard let button = self.statusItem.button else { return }
            
            if self.popover.isShown {
                self.popover.performClose(nil)
            } else {
                self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                self.popover.contentViewController?.view.window?.becomeKey()
            }
        }
    }
}
#else
class StatusBarController {
    init(popoverContent: some View) {
            // Stub implementation for iOS/iPadOS
    }
}
#endif
