import SwiftUI

struct RootView: View {
  @Bindable var shell: ApplicationShell

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
  }

  @ViewBuilder
  private var destinationView: some View {
    switch shell.selectedDestination {
    case .todayReview:
      PlaceholderView(
        title: AppDestination.todayReview.title,
        systemImage: AppDestination.todayReview.systemImage,
        description: AppDestination.todayReview.placeholderDescription
      )
    case .library:
      LearningLibraryView(shell: shell)
    case .settings:
      TranslationSettingsView(shell: shell)
    case nil:
      PlaceholderView(
        title: "TranStudy",
        systemImage: "character.book.closed",
        description: "从侧边栏选择一个区域。"
      )
    }
  }
}

private struct PlaceholderView: View {
  let title: String
  let systemImage: String
  let description: String

  var body: some View {
    ContentUnavailableView(
      title,
      systemImage: systemImage,
      description: Text(description)
    )
  }
}
