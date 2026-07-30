import AppKit
import SwiftUI

struct RootView: View {
  @Bindable var shell: ApplicationShell
  let onTranslateClipboard: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      if !shell.missingPreparationCapabilities.isEmpty {
        PreparationStatusBanner(shell: shell)
        Divider()
      }

      tabNavigation
    }
    .tint(
      shell.selectedDestination == .library
        ? .accentColor
        : TranStudyDesign.accentColor
    )
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(action: onTranslateClipboard) {
          Label("翻译剪贴板", systemImage: "character.bubble")
        }
        .help("翻译剪贴板（\(shell.translationShortcut.title)）")
      }
    }
    .sheet(
      isPresented: Binding(
        get: { shell.isPreparationPresented },
        set: { isPresented in
          if !isPresented {
            shell.completeInitialPreparation()
          }
        }
      )
    ) {
      InitialPreparationView(shell: shell)
    }
    .task {
      await shell.refreshPreparationStatus()
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: NSApplication.didBecomeActiveNotification
      )
    ) { _ in
      Task {
        await shell.refreshPreparationStatus()
      }
    }
  }

  @ViewBuilder
  private var tabNavigation: some View {
    if #available(macOS 15.0, *) {
      TabView(selection: $shell.selectedDestination) {
        ForEach(shell.destinations) { destination in
          Tab(
            destination.title,
            systemImage: destination.systemImage,
            value: destination
          ) {
            destinationView(for: destination)
          }
        }
      }
    } else {
      TabView(selection: $shell.selectedDestination) {
        ForEach(shell.destinations) { destination in
          destinationView(for: destination)
            .tabItem {
              Label(destination.title, systemImage: destination.systemImage)
            }
            .tag(destination)
        }
      }
    }
  }

  @ViewBuilder
  private func destinationView(for destination: AppDestination) -> some View {
    switch destination {
    case .todayReview:
      TodayReviewView(shell: shell)
    case .library:
      LearningLibraryView(shell: shell)
    case .settings:
      TranslationSettingsView(shell: shell)
    }
  }
}

#if DEBUG
  #Preview("主窗口") {
    PreviewFactory.rootView()
  }
#endif
