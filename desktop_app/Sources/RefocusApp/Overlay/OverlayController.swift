import AppKit
import SwiftUI

final class OverlayModel: ObservableObject {
    @Published var message: String = ""
    @Published var countdown: String = ""
}

final class OverlayController {
    private var windows: [NSWindow] = []
    private let model = OverlayModel()

    func show(message: String, countdown: String) {
        DispatchQueue.main.async {
            self.model.message = message
            self.model.countdown = countdown
            if self.windows.isEmpty {
                self.presentWindows()
            }
        }
    }

    func hide() {
        DispatchQueue.main.async {
            self.windows.forEach { $0.close() }
            self.windows.removeAll()
        }
    }

    private func presentWindows() {
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.ignoresMouseEvents = true
            window.contentView = NSHostingView(rootView: OverlayView(model: model))
            window.orderFrontRegardless()
            self.windows.append(window)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 24) {
                Text("This site is blocked")
                    .font(.system(size: 38, weight: .semibold))
                Text(model.message)
                    .font(.system(size: 24, weight: .medium))
                Text(model.countdown)
                    .font(.system(size: 90, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .multilineTextAlignment(.center)
            .foregroundColor(.red)
            .padding()
        }
    }
}
