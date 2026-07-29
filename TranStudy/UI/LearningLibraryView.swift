import SwiftUI

struct LearningLibraryView: View {
  @Bindable var shell: ApplicationShell
  @State private var editingItem: LearningItem?

  var body: some View {
    VStack(spacing: 0) {
      PageHeader(
        title: "单词库",
        subtitle: librarySubtitle,
        systemImage: "books.vertical.fill"
      )
      .frame(maxWidth: TranStudyDesign.pageWidth, alignment: .leading)
      .padding(.horizontal, 32)
      .padding(.top, 24)
      .padding(.bottom, 16)

      libraryToolbar
        .frame(maxWidth: TranStudyDesign.pageWidth)
        .padding(.horizontal, 32)
        .padding(.bottom, 16)

      Divider()

      if shell.displayedLearningItems.isEmpty {
        emptyLibrary
      } else {
        List(shell.displayedLearningItems) { item in
          libraryRow(item)
            .contentShape(.rect)
            .onTapGesture {
              if shell.isLibrarySelecting {
                shell.toggleLibrarySelection(item.id)
              }
            }
        }
        .listStyle(.inset)
      }
    }
    .task {
      await shell.refreshLibrary()
    }
    .sheet(item: $editingItem) { item in
      LearningItemEditorView(item: item) { canonicalForm, details in
        await shell.saveLearningItem(
          itemID: item.id,
          canonicalForm: canonicalForm,
          details: details
        )
      }
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

  private var libraryToolbar: some View {
    HStack(spacing: 12) {
      TranStudySegmentedControl(
        options: [LearningLibraryScope.active, .archived],
        selection: Binding(
          get: { shell.libraryScope },
          set: { shell.setLibraryScope($0) }
        ),
        label: {
          $0 == .active ? "学习中" : "已归档"
        },
        tint: {
          $0 == .archived ? .red : .accentColor
        }
      )
      .frame(width: 190)

      Spacer()

      if shell.isLibrarySelecting {
        Text("已选择 \(shell.selectedLearningItemIDs.count) 项")
          .font(.callout)
          .foregroundStyle(.secondary)

        Button("全选") {
          shell.selectAllLibraryItems()
        }
        .disabled(shell.displayedLearningItems.isEmpty)

        Button(shell.libraryScope == .active ? "归档" : "恢复") {
          Task {
            if shell.libraryScope == .active {
              await shell.archiveSelectedLibraryItems()
            } else {
              await shell.restoreSelectedLibraryItems()
            }
          }
        }
        .buttonStyle(.borderedProminent)
        .tint(shell.libraryScope == .active ? .red : .accentColor)
        .disabled(shell.selectedLearningItemIDs.isEmpty)

        Button("取消") {
          shell.cancelLibrarySelection()
        }
      } else {
        Button("选择") {
          shell.beginLibrarySelection()
        }
        .disabled(shell.displayedLearningItems.isEmpty)
      }
    }
  }

  private func libraryRow(_ item: LearningItem) -> some View {
    HStack(alignment: .top, spacing: 12) {
      if shell.isLibrarySelecting {
        Image(
          systemName:
            shell.selectedLearningItemIDs.contains(item.id)
            ? "checkmark.circle.fill"
            : "circle"
        )
        .font(.title3)
        .foregroundStyle(
          shell.selectedLearningItemIDs.contains(item.id)
            ? Color.accentColor
            : Color.secondary
        )
        .padding(.top, 2)
      }

      VStack(alignment: .leading, spacing: 9) {
        HStack(alignment: .firstTextBaseline) {
          Text(item.kind == .sentence ? item.sourceText : item.canonicalForm)
            .font(.title3.weight(.semibold))
          if !item.pronunciation.isEmpty {
            Text(item.pronunciation)
              .foregroundStyle(.secondary)
          }
          Spacer()

          if !shell.isLibrarySelecting {
            Button {
              editingItem = item
            } label: {
              Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .help("编辑学习内容")
            .accessibilityLabel("编辑 \(item.canonicalForm)")
          }

          if item.kind == .sentence {
            Text("句子卡")
              .font(.caption.weight(.medium))
              .foregroundStyle(.purple)
              .padding(.horizontal, 8)
              .padding(.vertical, 3)
              .background(.purple.opacity(0.1), in: .capsule)
          } else if !item.partOfSpeech.isEmpty {
            Text(item.partOfSpeech)
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary)
              .padding(.horizontal, 8)
              .padding(.vertical, 3)
              .background(.quaternary, in: .capsule)
          }
        }

        if item.kind == .sentence {
          Text(item.sentenceTranslation)
            .font(.body)
            .foregroundStyle(.secondary)
        } else {
          Text(item.contextualMeaning.isEmpty ? item.sourceText : item.contextualMeaning)
            .font(.body.weight(.medium))

          if !item.exampleSentence.isEmpty {
            Text(item.exampleSentence)
              .italic()
              .foregroundStyle(.secondary)
          }

          if !item.sentenceTranslation.isEmpty {
            Text(item.sentenceTranslation)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }

        if !item.userNote.isEmpty {
          Label(item.userNote, systemImage: "note.text")
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        if !item.customExamples.isEmpty {
          DisclosureGroup("\(item.customExamples.count) 个自定义例句") {
            VStack(alignment: .leading, spacing: 10) {
              ForEach(item.customExamples) { example in
                VStack(alignment: .leading, spacing: 3) {
                  Text(example.englishText)
                    .italic()
                  if !example.chineseTranslation.isEmpty {
                    Text(example.chineseTranslation)
                      .foregroundStyle(.secondary)
                  }
                }
              }
            }
            .padding(.top, 6)
          }
          .font(.callout)
        }

        encounterSummary(item)
      }
      .padding(.vertical, 10)
    }
  }

  private func encounterSummary(_ item: LearningItem) -> some View {
    VStack(alignment: .leading, spacing: 7) {
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
        DisclosureGroup(
          item.kind == .sentence
            ? "\(item.encounters.count) 次遇见"
            : "\(item.encounters.count) 次真实语境"
        ) {
          VStack(alignment: .leading, spacing: 12) {
            ForEach(item.encounters) { encounter in
              encounterView(encounter, kind: item.kind)
            }
          }
          .padding(.top, 8)
        }
        .font(.callout)
      }
    }
  }

  private var librarySubtitle: String {
    if shell.learningItems.isEmpty, shell.archivedLearningItems.isEmpty {
      return "从真实语境中积累值得记住的单词、短语和句子。"
    }
    return
      "学习中 \(shell.learningItems.count) 条，已归档 \(shell.archivedLearningItems.count) 条。"
  }

  private var emptyLibrary: some View {
    VStack(spacing: 15) {
      Image(systemName: shell.libraryScope == .active ? "text.book.closed" : "archivebox")
        .font(.system(size: 30, weight: .medium))
        .foregroundStyle(.tint)
        .frame(width: 62, height: 62)
        .background(.tint.opacity(0.1), in: .circle)

      Text(shell.libraryScope == .active ? "从第一个词开始" : "还没有归档内容")
        .font(.title3.weight(.semibold))

      if shell.libraryScope == .active {
        Text(
          "复制一个英文单词或短语，按 \(shell.translationShortcut.title) 翻译，确认内容后选择“加入学习”。"
        )
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 380)
      } else {
        Text("归档的单词卡和句子卡会保留全部资料，并可随时恢复。")
          .foregroundStyle(.secondary)
      }
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

  private func encounterView(
    _ encounter: LearningEncounter,
    kind: LearningContentKind
  ) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text(encounter.sourceText)
          .fontWeight(.semibold)
        if kind == .word, !encounter.pronunciation.isEmpty {
          Text(encounter.pronunciation)
            .foregroundStyle(.secondary)
        }
        if kind == .word, !encounter.partOfSpeech.isEmpty {
          Text(encounter.partOfSpeech)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Text(encounter.encounteredAt, format: .dateTime.year().month().day())
          .font(.caption)
          .foregroundStyle(.tertiary)
      }

      if kind == .word, !encounter.contextualMeaning.isEmpty {
        Text(encounter.contextualMeaning)
      }
      if kind == .word, !encounter.exampleSentence.isEmpty {
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

private struct LearningItemEditorView: View {
  let item: LearningItem
  let onSave: (String, LearningItemDetailsUpdate) async -> Bool
  @Environment(\.dismiss) private var dismiss
  @State private var canonicalForm: String
  @State private var pronunciation: String
  @State private var partOfSpeech: String
  @State private var contextualMeaning: String
  @State private var exampleSentence: String
  @State private var sentenceTranslation: String
  @State private var userNote: String
  @State private var customExamples: [EditableCustomExample]
  @State private var isSaving = false
  @State private var saveFailed = false

  init(
    item: LearningItem,
    onSave: @escaping (String, LearningItemDetailsUpdate) async -> Bool
  ) {
    self.item = item
    self.onSave = onSave
    _canonicalForm = State(initialValue: item.canonicalForm)
    _pronunciation = State(initialValue: item.pronunciation)
    _partOfSpeech = State(initialValue: item.partOfSpeech)
    _contextualMeaning = State(initialValue: item.contextualMeaning)
    _exampleSentence = State(initialValue: item.exampleSentence)
    _sentenceTranslation = State(initialValue: item.sentenceTranslation)
    _userNote = State(initialValue: item.userNote)
    _customExamples = State(
      initialValue: item.customExamples.map(EditableCustomExample.init)
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(item.kind == .word ? "编辑词条" : "编辑句子卡")
            .font(.title2.weight(.semibold))
          Text("真实遇词历史会保持原样。")
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding(24)

      Divider()

      Form {
        if item.kind == .word {
          Section("词条资料") {
            TextField("规范词形", text: $canonicalForm)
            TextField("音标", text: $pronunciation)
            TextField("词性", text: $partOfSpeech)
            TextField("释义", text: $contextualMeaning, axis: .vertical)
          }
        }

        Section(item.kind == .word ? "主要例句" : "句子翻译") {
          if item.kind == .word {
            TextField("英文例句", text: $exampleSentence, axis: .vertical)
          }
          TextField("中文翻译", text: $sentenceTranslation, axis: .vertical)
        }

        Section("个人笔记") {
          TextEditor(text: $userNote)
            .frame(minHeight: 80)
        }

        Section {
          ForEach($customExamples) { $example in
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                TextField("英文例句", text: $example.englishText, axis: .vertical)
                Button(role: .destructive) {
                  customExamples.removeAll { $0.id == example.id }
                } label: {
                  Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除自定义例句")
              }
              TextField("中文翻译（可选）", text: $example.chineseTranslation, axis: .vertical)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
          }

          Button {
            customExamples.append(EditableCustomExample())
          } label: {
            Label("添加自定义例句", systemImage: "plus")
          }
        } header: {
          Text("自定义例句")
        } footer: {
          Text("自定义例句与真实遇词历史分开保存。")
        }
      }
      .formStyle(.grouped)

      Divider()

      HStack {
        if saveFailed {
          Label("保存失败，请检查后重试", systemImage: "exclamationmark.circle")
            .font(.callout)
            .foregroundStyle(.red)
        }
        Spacer()
        Button("取消", role: .cancel) {
          dismiss()
        }
        Button("保存") {
          Task {
            isSaving = true
            saveFailed = false
            let didSave = await onSave(
              canonicalForm,
              LearningItemDetailsUpdate(
                pronunciation: pronunciation,
                partOfSpeech: partOfSpeech,
                contextualMeaning: contextualMeaning,
                exampleSentence: exampleSentence,
                sentenceTranslation: sentenceTranslation,
                userNote: userNote,
                customExamples: customExamples.map(\.learningExample)
              )
            )
            isSaving = false
            if didSave {
              dismiss()
            } else {
              saveFailed = true
            }
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          isSaving
            || (item.kind == .word
              && canonicalForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        )
      }
      .padding(20)
    }
    .frame(width: 620, height: 680)
  }
}

private struct EditableCustomExample: Identifiable {
  let id: UUID
  var englishText: String
  var chineseTranslation: String

  init(
    id: UUID = UUID(),
    englishText: String = "",
    chineseTranslation: String = ""
  ) {
    self.id = id
    self.englishText = englishText
    self.chineseTranslation = chineseTranslation
  }

  init(_ example: LearningCustomExample) {
    self.init(
      id: example.id,
      englishText: example.englishText,
      chineseTranslation: example.chineseTranslation
    )
  }

  var learningExample: LearningCustomExample {
    LearningCustomExample(
      id: id,
      englishText: englishText,
      chineseTranslation: chineseTranslation
    )
  }
}

#if DEBUG
  #Preview("单词库") {
    PreviewFactory.learningLibraryView()
  }
#endif
