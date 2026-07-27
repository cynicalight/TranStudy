import SwiftUI

struct LearningLibraryView: View {
  let shell: ApplicationShell

  var body: some View {
    Group {
      if shell.learningItems.isEmpty {
        ContentUnavailableView(
          "单词库",
          systemImage: "books.vertical",
          description: Text("按 F5 翻译剪贴板中的单词，再点击“加入学习”。")
        )
      } else {
        List(shell.learningItems) { item in
          VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
              Text(item.canonicalForm)
                .font(.title3.weight(.semibold))
              if !item.pronunciation.isEmpty {
                Text(item.pronunciation)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Text(item.partOfSpeech)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text(item.contextualMeaning)
            Text(item.exampleSentence)
              .foregroundStyle(.secondary)
            Text(item.sentenceTranslation)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 6)
        }
        .navigationTitle("单词库")
      }
    }
    .task {
      await shell.refreshLibrary()
    }
  }
}
