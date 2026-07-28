import SwiftUI

struct RootView: View {
  @Bindable var shell: ApplicationShell
  let onTranslateClipboard: () -> Void

  var body: some View {
    NavigationSplitView {
      List(
        shell.destinations,
        selection: $shell.selectedDestination
      ) { destination in
        Label(destination.title, systemImage: destination.systemImage)
          .tag(destination)
      }
      .navigationTitle("TranStudy")
      .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    } detail: {
      destinationView
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(action: onTranslateClipboard) {
          Label("翻译剪贴板", systemImage: "character.bubble")
        }
        .help("翻译剪贴板（F5）")
      }
    }
  }

  @ViewBuilder
  private var destinationView: some View {
    switch shell.selectedDestination {
    case .todayReview:
      TodayReviewView(shell: shell)
    case .library:
      LearningLibraryView(shell: shell)
    case .settings:
      TranslationSettingsView(shell: shell)
    case nil:
      ContentUnavailableView(
        "TranStudy",
        systemImage: "character.book.closed",
        description: Text("从侧边栏选择一个区域。")
      )
    }
  }
}

#if DEBUG
  #Preview("主窗口") {
    PreviewFactory.rootView()
  }
#endif
