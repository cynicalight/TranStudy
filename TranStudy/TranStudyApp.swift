import SwiftData
import SwiftUI

@main
struct TranStudyApp: App {
  @State private var shell: ApplicationShell

  init() {
    do {
      let container = try ModelContainer(for: LearningRecord.self)
      let learningStore = SwiftDataLearningStore(container: container)
      _shell = State(
        initialValue: ApplicationShell(
          environment: .live(learningStore: learningStore)
        ))
    } catch {
      fatalError("Unable to initialize the learning store: \(error)")
    }
  }

  var body: some Scene {
    WindowGroup {
      RootView(shell: shell)
        .frame(minWidth: 720, minHeight: 480)
        .task {
          await shell.refreshTodayReview()
        }
    }
  }
}
