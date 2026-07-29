import SwiftUI

struct LearningLibraryView: View {
  @Bindable var shell: ApplicationShell
  @State private var editingItem: LearningItem?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        PageHeader(
          title: "单词库",
          subtitle: librarySubtitle,
          systemImage: "books.vertical.fill"
        )
        .frame(maxWidth: TranStudyDesign.pageWidth, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 24)
        .padding(.bottom, 16)

        if !shell.isLibrarySelecting {
          librarySearchField
            .transition(.move(edge: .leading).combined(with: .opacity))
        }
        libraryToolbar
      }
      .animation(
        reduceMotion ? nil : .easeInOut(duration: 0.2),
        value: shell.isLibrarySelecting
      )
      .padding(.horizontal, 12)

      Divider()

      if shell.displayedLearningItems.isEmpty {
        emptyLibrary
      } else {
        List(shell.displayedLearningItems) { item in
          libraryRow(item)
            .contentShape(.rect)
        }
        .listStyle(.inset)
      }
    }
    .task {
      await shell.refreshLibrary()
    }
    .sheet(item: $editingItem) { item in
      LearningItemEditorView(
        item: item,
        onSave: { canonicalForm, details in
          await shell.saveLearningItem(
            itemID: item.id,
            canonicalForm: canonicalForm,
            details: details
          )
        },
        onDelete: {
          await shell.stageLibraryItemDeletion(itemID: item.id)
        },
        scheduleActions: LearningReviewScheduleActions(
          setNextReviewDate: { nextReviewAt in
            await shell.setLearningItemNextReviewDate(
              itemID: item.id,
              nextReviewAt: nextReviewAt
            )
          },
          setPaused: { isPaused in
            await shell.setLearningItemReviewPaused(
              itemID: item.id,
              isPaused: isPaused
            )
          },
          reset: {
            await shell.resetLearningItemReviewProgress(itemID: item.id)
          }
        )
      )
    }
    .safeAreaInset(edge: .bottom) {
      if let pendingDeletion = shell.pendingLibraryDeletion {
        libraryDeletionBanner(pendingDeletion)
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

  private func libraryDeletionBanner(_ item: LearningItem) -> some View {
    HStack(spacing: 12) {
      Label(
        "已删除“\(item.kind == .sentence ? item.sourceText : item.canonicalForm)”",
        systemImage: "trash"
      )
      .lineLimit(1)
      Spacer()
      Button("撤销") {
        Task {
          await shell.undoLibraryItemDeletion()
        }
      }
      .buttonStyle(.borderedProminent)
      .keyboardShortcut("z", modifiers: .command)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(.regularMaterial)
    .overlay(alignment: .top) {
      Divider()
    }
  }

  private var librarySearchField: some View {
    HStack(spacing: 7) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField(
        "搜索词形或例句",
        text: $shell.librarySearchQuery
      )
      .textFieldStyle(.plain)
      .frame(width: 180)

      if !shell.librarySearchQuery.isEmpty {
        Button {
          shell.librarySearchQuery = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("清除搜索")
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(.quaternary.opacity(0.7), in: .rect(cornerRadius: 8))
  }

  private var libraryToolbar: some View {
    HStack {

      if shell.isLibrarySelecting {
        Group {
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
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
      } else {
        Button {
          shell.beginLibrarySelection()
        } label: {
          Image(systemName: "checkmark")
            .font(.callout.weight(.semibold))
            .frame(width: 30, height: 30)
            .contentShape(.circle)
            .adaptiveGlass(cornerRadius: 15)
        }
        .buttonStyle(.plain)
        .help("选择")
        .accessibilityLabel("选择")
        .disabled(shell.displayedLearningItems.isEmpty)
        .transition(.opacity.combined(with: .move(edge: .trailing)))
      }

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
      .frame(width: 160)
    }
    .animation(
      reduceMotion ? nil : .easeInOut(duration: 0.2),
      value: shell.isLibrarySelecting
    )
  }

  private func libraryRow(_ item: LearningItem) -> some View {
    HStack(alignment: .center, spacing: 12) {
      if shell.isLibrarySelecting {
        let isSelected = shell.selectedLearningItemIDs.contains(item.id)
        Button {
          shell.toggleLibrarySelection(item.id)
        } label: {
          Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          "\(isSelected ? "取消选择" : "选择") \(item.kind == .sentence ? item.sourceText : item.canonicalForm)"
        )
        .accessibilityValue(isSelected ? "已选择" : "未选择")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            .disabled(shell.pendingLibraryDeletion != nil)
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
      Image(systemName: emptyLibraryIcon)
        .font(.system(size: 30, weight: .medium))
        .foregroundStyle(.tint)
        .frame(width: 62, height: 62)
        .background(.tint.opacity(0.1), in: .circle)

      Text(emptyLibraryTitle)
        .font(.title3.weight(.semibold))

      if !shell.librarySearchQuery.isEmpty {
        Text("没有找到与“\(shell.librarySearchQuery)”匹配的词形或例句。")
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      } else if shell.libraryScope == .active {
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

  private var emptyLibraryIcon: String {
    if !shell.librarySearchQuery.isEmpty {
      return "magnifyingglass"
    }
    return shell.libraryScope == .active ? "text.book.closed" : "archivebox"
  }

  private var emptyLibraryTitle: String {
    if !shell.librarySearchQuery.isEmpty {
      return "没有搜索结果"
    }
    return shell.libraryScope == .active ? "从第一个词开始" : "还没有归档内容"
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
  let onDelete: () async -> Bool
  let scheduleActions: LearningReviewScheduleActions
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
  @State private var deleteFailed = false
  @State private var isDeleteConfirmationPresented = false

  init(
    item: LearningItem,
    onSave: @escaping (String, LearningItemDetailsUpdate) async -> Bool,
    onDelete: @escaping () async -> Bool,
    scheduleActions: LearningReviewScheduleActions
  ) {
    self.item = item
    self.onSave = onSave
    self.onDelete = onDelete
    self.scheduleActions = scheduleActions
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

        LearningReviewScheduleEditor(
          item: item,
          actions: scheduleActions
        )

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

        if let latestEncounter = item.encounters.first {
          Section("最近遇见") {
            encounterDetails(latestEncounter)
          }
        }

        let historicalEncounters = Array(item.encounters.dropFirst())
        if !historicalEncounters.isEmpty {
          Section("历史遇见") {
            ForEach(historicalEncounters) { encounter in
              encounterDetails(encounter)
            }
          }
        }
      }
      .formStyle(.grouped)

      Divider()

      HStack {
        Button(item.kind == .word ? "删除词条" : "删除句子卡", role: .destructive) {
          isDeleteConfirmationPresented = true
        }
        .foregroundStyle(.red)
        .disabled(isSaving)

        if saveFailed || deleteFailed {
          Label(
            saveFailed ? "保存失败，请检查后重试" : "删除失败，请重试",
            systemImage: "exclamationmark.circle"
          )
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
    .alert(
      item.kind == .word ? "删除这个词条？" : "删除这张句子卡？",
      isPresented: $isDeleteConfirmationPresented
    ) {
      Button("取消", role: .cancel) {}
      Button("删除", role: .destructive) {
        Task {
          deleteFailed = false
          if await onDelete() {
            dismiss()
          } else {
            deleteFailed = true
          }
        }
      }
    } message: {
      Text("删除后可在约十秒内撤销；随后会永久删除相关释义、例句、遇见记录和复习记录。")
    }
  }

  private func encounterDetails(_ encounter: LearningEncounter) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        Text(encounter.sourceText)
          .fontWeight(.semibold)
        if item.kind == .word, !encounter.partOfSpeech.isEmpty {
          Text(encounter.partOfSpeech)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      if item.kind == .word, !encounter.contextualMeaning.isEmpty {
        Text(encounter.contextualMeaning)
      }

      if !encounter.exampleSentence.isEmpty,
        encounter.exampleSentence != encounter.sourceText
      {
        Text(encounter.exampleSentence)
          .italic()
      }
      if !encounter.sentenceTranslation.isEmpty {
        Text(encounter.sentenceTranslation)
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 5) {
        Label(encounter.sourceApplicationName, systemImage: "app")
        Text("·")
        Text(
          encounter.encounteredAt,
          format: .dateTime.year().month().day().hour().minute()
        )
      }
      .font(.caption)
      .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 4)
  }
}

private struct LearningReviewScheduleActions {
  let setNextReviewDate: (Date) async -> Bool
  let setPaused: (Bool) async -> Bool
  let reset: () async -> Date?
}

private struct LearningReviewScheduleEditor: View {
  let item: LearningItem
  let actions: LearningReviewScheduleActions
  @State private var nextReviewAt: Date
  @State private var isPaused: Bool
  @State private var isUpdating = false
  @State private var updateFailed = false
  @State private var isResetConfirmationPresented = false

  init(
    item: LearningItem,
    actions: LearningReviewScheduleActions
  ) {
    self.item = item
    self.actions = actions
    _nextReviewAt = State(initialValue: item.nextReviewAt ?? item.createdAt)
    _isPaused = State(initialValue: item.isPaused)
  }

  var body: some View {
    Section {
      HStack {
        Text("当前状态")
        Spacer()
        Label(reviewStatus.label, systemImage: reviewStatus.systemImage)
          .foregroundStyle(reviewStatus.color)
      }

      DatePicker(
        "下次复习日期",
        selection: $nextReviewAt,
        displayedComponents: .date
      )

      HStack {
        Button("更新日期") {
          Task {
            isUpdating = true
            updateFailed = false
            let didUpdate = await actions.setNextReviewDate(nextReviewAt)
            isUpdating = false
            updateFailed = !didUpdate
          }
        }

        Button(isPaused ? "恢复复习" : "暂停复习") {
          Task {
            isUpdating = true
            updateFailed = false
            let updatedPauseState = !isPaused
            let didUpdate = await actions.setPaused(updatedPauseState)
            isUpdating = false
            if didUpdate {
              isPaused = updatedPauseState
            } else {
              updateFailed = true
            }
          }
        }

        Spacer()

        Button("重置学习进度", role: .destructive) {
          isResetConfirmationPresented = true
        }
      }
      .disabled(isUpdating)

      if updateFailed {
        Label("排程更新失败，请重试", systemImage: "exclamationmark.circle")
          .font(.callout)
          .foregroundStyle(.red)
      }
    } header: {
      Text("复习排程")
    } footer: {
      Text(scheduleExplanation)
    }
    .alert("重置学习进度？", isPresented: $isResetConfirmationPresented) {
      Button("取消", role: .cancel) {}
      Button("确认重置", role: .destructive) {
        Task {
          isUpdating = true
          updateFailed = false
          let persistedResetAt = await actions.reset()
          isUpdating = false
          if let persistedResetAt {
            nextReviewAt = persistedResetAt
          } else {
            updateFailed = true
          }
        }
      }
    } message: {
      Text("复习历史和当前学习进度将被清除，词条内容与遇见记录不会改变。")
    }
  }

  private var reviewStatus: (label: String, systemImage: String, color: Color) {
    if item.archivedAt != nil {
      return ("已归档", "archivebox.fill", .red)
    }
    if isPaused {
      return ("已暂停", "pause.circle.fill", .orange)
    }
    return ("学习中", "checkmark.circle.fill", .green)
  }

  private var scheduleExplanation: String {
    if item.archivedAt != nil {
      return "归档期间不会进入复习队列；排程调整会在恢复后生效。重置仍会清除复习历史。"
    }
    return "重置会清除复习历史并让卡片从今天重新开始；暂停状态会保持不变。"
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
