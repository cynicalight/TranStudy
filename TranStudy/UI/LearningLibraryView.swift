import SwiftUI

struct LearningLibraryView: View {
  @Bindable var shell: ApplicationShell
  @State private var editingItem: LearningItem?
  @State private var editedCanonicalForm = ""

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
              Button {
                editedCanonicalForm = item.canonicalForm
                editingItem = item
              } label: {
                Image(systemName: "pencil")
              }
              .buttonStyle(.borderless)
              .help("修改词典原形")
              .accessibilityLabel("修改 \(item.canonicalForm) 的词典原形")

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
              Text(
                item.encounters.first?.encounteredAt ?? item.createdAt,
                format: .dateTime.year().month().day()
              )
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

            if !item.encounters.isEmpty {
              DisclosureGroup("\(item.encounters.count) 次真实语境") {
                VStack(alignment: .leading, spacing: 12) {
                  ForEach(item.encounters) { encounter in
                    encounterView(encounter)
                  }
                }
                .padding(.top, 8)
              }
              .font(.callout)
            }
          }
          .padding(.vertical, 10)
        }
        .listStyle(.inset)
      }
    }
    .navigationTitle("单词库")
    .task {
      await shell.refreshLibrary()
    }
    .sheet(item: $editingItem) { item in
      VStack(alignment: .leading, spacing: 18) {
        Text("修改词典原形")
          .font(.title2.weight(.semibold))

        Text("修改后会用规范化词形检查重复；已有语境不会丢失。")
          .foregroundStyle(.secondary)

        TextField("词典原形", text: $editedCanonicalForm)
          .textFieldStyle(.roundedBorder)

        HStack {
          Spacer()
          Button("取消", role: .cancel) {
            editingItem = nil
          }
          Button("保存") {
            Task {
              await shell.updateLearningItemCanonicalForm(
                itemID: item.id,
                canonicalForm: editedCanonicalForm
              )
              editingItem = nil
            }
          }
          .buttonStyle(.borderedProminent)
          .disabled(
            editedCanonicalForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          )
        }
      }
      .padding(24)
      .frame(width: 420)
    }
    .alert(
      "合并到已有词条？",
      isPresented: pendingLibraryMergeBinding,
      presenting: shell.pendingLibraryMerge
    ) { _ in
      Button("取消", role: .cancel) {
        shell.cancelPendingLibraryMerge()
      }
      Button("确认合并") {
        Task {
          await shell.confirmPendingLibraryMerge()
        }
      }
    } message: { summary in
      Text(
        "“\(summary.incomingSourceText)”将合并到“\(summary.canonicalForm)”。"
          + "合并后会保留双方的释义、例句和全部语境。"
      )
    }
  }

  private var librarySubtitle: String {
    if shell.learningItems.isEmpty {
      return "从真实语境中积累值得记住的单词和短语。"
    }
    return "已收录 \(shell.learningItems.count) 条学习内容，按最近遇见排序。"
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

      Text(
        "复制一个英文单词或短语，按 \(shell.translationShortcut.title) 翻译，确认内容后选择“加入学习”。"
      )
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .frame(maxWidth: 380)

      Label("快速翻译  \(shell.translationShortcut.title)", systemImage: "keyboard")
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

  private var pendingLibraryMergeBinding: Binding<Bool> {
    Binding(
      get: { shell.pendingLibraryMerge != nil },
      set: { _ in }
    )
  }

  private func encounterView(_ encounter: LearningEncounter) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text(encounter.sourceText)
          .fontWeight(.semibold)
        if !encounter.pronunciation.isEmpty {
          Text(encounter.pronunciation)
            .foregroundStyle(.secondary)
        }
        if !encounter.partOfSpeech.isEmpty {
          Text(encounter.partOfSpeech)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Text(encounter.encounteredAt, format: .dateTime.year().month().day())
          .font(.caption)
          .foregroundStyle(.tertiary)
      }

      if !encounter.contextualMeaning.isEmpty {
        Text(encounter.contextualMeaning)
      }
      if !encounter.exampleSentence.isEmpty {
        Text(encounter.exampleSentence)
          .italic()
          .foregroundStyle(.secondary)
      }
      if !encounter.sentenceTranslation.isEmpty {
        Text(encounter.sentenceTranslation)
          .foregroundStyle(.secondary)
      }
      Label(encounter.sourceApplicationName, systemImage: "app")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
  }
}

#if DEBUG
  #Preview("单词库") {
    PreviewFactory.learningLibraryView()
  }
#endif
