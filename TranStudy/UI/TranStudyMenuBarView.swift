import AppKit
import SwiftUI

@MainActor
struct TranStudyMenuBarView: View {
  @Bindable var shell: ApplicationShell
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("打开 TranStudy") {
      presentMainWindow(using: openWindow)
    }

    Button("开始今日复习（\(shell.learningSummary.dueCount)）") {
      Task {
        await shell.startTodayReview()
      }
      presentMainWindow(using: openWindow)
    }

    Divider()

    Button(
      shell.selectionConfiguration.isEnabled ? "暂停划词" : "恢复划词"
    ) {
      shell.setSelectionEnabled(!shell.selectionConfiguration.isEnabled)
    }

    Divider()

    Button("退出 TranStudy") {
      NSApplication.shared.terminate(nil)
    }
  }

}

@MainActor
struct NotificationRoutingBridge: View {
  let shell: ApplicationShell
  let notifier: SystemReviewNotifier
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Color.clear
      .frame(width: 0, height: 0)
      .onAppear {
        notifier.start()
        notifier.onReviewRequested = {
          Task {
            await shell.startTodayReview()
          }
          presentMainWindow(using: openWindow)
        }
      }
  }
}

@MainActor
private func presentMainWindow(using openWindow: OpenWindowAction) {
  openWindow(id: "main")
  NSApplication.shared.activate(ignoringOtherApps: true)
}
