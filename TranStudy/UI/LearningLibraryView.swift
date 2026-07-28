import SwiftUI

struct LearningLibraryView: View {
  let shell: ApplicationShell

  var body: some View {
    VStack(spacing: 0) {
      PageHeader(
        title: "单词库",
        subtitle: librarySubtitle,
        systemImage: "books.vertical.fill"
      )
      .frame(maxWidth: TranStudyDesign.pageWidth, alignment: .leading)
      .padding(.horizontal, 32)
      .padding(.vertical, 24)

      Divider()

      if shell.learningItems.isEmpty {
        emptyLibrary
      } else {
        List(shell.learningItems) { item in
          VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
              Text(item.canonicalForm)
                .font(.title3.weight(.semibold))
              if !item.pronunciation.isEmpty {
                Text(item.pronunciation)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              if !item.partOfSpeech.isEmpty {
                Text(item.partOfSpeech)
                  .font(.caption.weight(.medium))
                  .foregroundStyle(.secondary)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 3)
                  .background(.quaternary, in: .capsule)
              }
            }

            Text(item.contextualMeaning.isEmpty ? item.sourceText : item.contextualMeaning)
              .font(.body.weight(.medium))

            Text(item.exampleSentence)
              .italic()
              .foregroundStyle(.secondary)

            Text(item.sentenceTranslation)
              .font(.callout)
              .foregroundStyle(.secondary)

            HStack(spacing: 5) {
              Image(systemName: "doc.on.clipboard")
              Text(item.sourceApplicationName)
              Text("·")
              Text(item.createdAt, format: .dateTime.year().month().day())
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
          }
          .padding(.vertical, 10)
          .accessibilityElement(children: .combine)
        }
        .listStyle(.inset)
      }
    }
    .navigationTitle("单词库")
    .task {
      await shell.refreshLibrary()
    }
  }

  private var librarySubtitle: String {
    if shell.learningItems.isEmpty {
      return "从真实语境中积累值得记住的单词和短语。"
    }
    return "已收录 \(shell.learningItems.count) 条学习内容，按最近加入排序。"
  }

  private var emptyLibrary: some View {
    VStack(spacing: 15) {
      Image(systemName: "text.book.closed")
        .font(.system(size: 30, weight: .medium))
        .foregroundStyle(.tint)
        .frame(width: 62, height: 62)
        .background(.tint.opacity(0.1), in: .circle)

      Text("从第一个词开始")
        .font(.title3.weight(.semibold))

      Text("复制一个英文单词或短语，按 F5 翻译，确认内容后选择“加入学习”。")
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 380)

      Label("快速翻译  F5", systemImage: "keyboard")
        .font(.callout.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.quaternary, in: .capsule)
    }
    .padding(32)
    .frame(maxWidth: 520)
    .contentSurface()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(32)
  }
}

#if DEBUG
  #Preview("单词库") {
    PreviewFactory.learningLibraryView()
  }
#endif
