import SwiftUI

struct RootView: View {
  @Bindable var shell: ApplicationShell
  let onTranslateClipboard: () -> Void

  var body: some View {
    TabView(selection: $shell.selectedDestination) {
      ForEach(shell.destinations) { destination in
        destinationView(for: destination)
          .tabItem {
            Label(destination.title, systemImage: destination.systemImage)
          }
          .tag(destination)
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(action: onTranslateClipboard) {
          Label("翻译剪贴板", systemImage: "character.bubble")
        }
        .help("翻译剪贴板（\(shell.translationShortcut.title)）")
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
