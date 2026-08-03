import SwiftUI

enum TranslationPanelMetrics {
  static let width: CGFloat = 500
  static let defaultHeight: CGFloat = 470
}

struct TranslationPanelView: View {
  @Bindable var shell: ApplicationShell
  let onDismiss: () -> Void
  let onTranslateLongTextSelection: (NSRange) -> Void
  let onAddLongTextSentence: () -> Void
  var onContentSizeChange: (CGSize, Bool) -> Void = { _, _ in }
  @State private var longTextLoadingContentHeight: CGFloat = 24

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      panelHeader

      content
    }
    .padding(14)
    .frame(width: TranslationPanelMetrics.width)
    .modifier(ContentFittingHeight(enabled: fitsPanelHeightToContent))
    .onGeometryChange(for: CGSize.self) { proxy in
      proxy.size
    } action: { size in
      onContentSizeChange(size, fitsPanelHeightToContent)
    }
    .onExitCommand(perform: onDismiss)
    .alert(
      "无法加入学习",
      isPresented: learningAdditionErrorBinding
    ) {
      Button("好", role: .cancel) {
        shell.clearLearningAdditionError()
      }
    } message: {
      Text(shell.learningAdditionErrorMessage ?? "")
    }
    .alert(
      "合并到已有词条？",
      isPresented: pendingMergeBinding,
      presenting: shell.pendingLearningMerge
    ) { _ in
      Button("取消", role: .cancel) {
        shell.cancelPendingLearningMerge()
      }
      Button("确认合并") {
        Task {
          await shell.confirmPendingLearningMerge()
          if shell.translationDraft == nil {
            onDismiss()
          }
        }
      }
    } message: { summary in
      Text(
        shell.localizedFormat(
          "“%@”将合并到“%@”。已有 %@ 条语境会全部保留，并新增当前语境。",
          summary.incomingSourceText,
          summary.canonicalForm,
          "\(summary.existingEncounterCount)"
        )
      )
    }
  }

  private var panelHeader: some View {
    HStack(spacing: 11) {
      Image(systemName: "character.bubble.fill")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(TranStudyDesign.accentColor)
        .frame(width: 32, height: 32)
        .background(
          TranStudyDesign.accentColor.opacity(0.1),
          in: .rect(cornerRadius: 9)
        )

      VStack(alignment: .leading, spacing: 1) {
        Text(LocalizedStringKey(shell.translationPresentationTitle))
          .font(.headline)
        Text("按 Esc 关闭")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

    }
    .padding(10)
    .adaptiveGlass(cornerRadius: 13)
  }

  @ViewBuilder
  private var content: some View {
    switch shell.translationStatus {
    case .idle, .loading:
      if shell.translationPresentationTitle == "翻译长文本" {
        longTextLoadingView
      } else {
        HStack(spacing: 10) {
          ProgressView()
            .controlSize(.small)
          VStack(alignment: .leading, spacing: 3) {
            Text("正在翻译")
              .font(.headline)
            Text("正在理解剪贴板中的语境…")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
      }
    case .failed:
      VStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 28))
          .foregroundStyle(.orange)
        Text("翻译失败")
          .font(.title3.weight(.semibold))
        Text(
          shell.localized(
            shell.translationError?.userFacingMessageKey
              ?? "请检查翻译服务设置和网络，然后重试。"
          )
        )
        .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, minHeight: 220)
    case .ready:
      if let longTextTranslation = shell.longTextTranslation {
        LongTextTranslationView(
          shell: shell,
          result: longTextTranslation,
          onTranslateSelection: onTranslateLongTextSelection,
          onAddSentence: onAddLongTextSentence
        )
      } else if shell.translationDraft != nil {
        draftForm
      }
    }
  }

  private var longTextLoadingView: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("英文原文")
        .font(.caption)
        .foregroundStyle(.secondary)
      ScrollView {
        Text(shell.translationSourceText)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
          } action: { height in
            longTextLoadingContentHeight = height
          }
      }
      .frame(height: longTextBlockHeight(for: longTextLoadingContentHeight))

      HStack(spacing: 10) {
        ProgressView()
          .controlSize(.small)
        Text("正在翻译完整内容…")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private var fitsPanelHeightToContent: Bool {
    shell.isLongTextTranslationPresentation || shell.translationDraft != nil
  }

  private func longTextBlockHeight(for contentHeight: CGFloat) -> CGFloat {
    min(max(contentHeight, 1), 180)
  }

  private var draftForm: some View {
    VStack(alignment: .leading, spacing: 14) {
      if !shell.translationSourceText.isEmpty {
        HStack(alignment: .bottom, spacing: 14) {
          VStack(alignment: .leading, spacing: 5) {
            Text("原文")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(shell.translationSourceText)
              .font(.title3.weight(.semibold))
              .lineLimit(2)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
            SpeechButton(text: shell.translationSourceText, speak: shell.speak)
          }

          DraftField(
            title: "原文音标",
            text: binding(\.pronunciation)
          )
          .frame(width: 150)
        }
      }

      Divider()

      HStack {
        DraftField(
          title: "词典原形",
          text: binding(\.canonicalForm)
        )
        DraftField(
          title: "词性",
          text: binding(\.partOfSpeech)
        )
        .frame(width: 110)
      }

      DraftField(
        title: "语境释义",
        text: binding(\.contextualMeaning)
      )

      HStack(alignment: .bottom, spacing: 8) {
        DraftField(
          title: "例句",
          text: binding(\.exampleSentence),
          axis: .vertical
        )
        SpeechButton(
          text: shell.translationDraft?.exampleSentence ?? "",
          speak: shell.speak
        )
      }

      DraftField(
        title: "例句翻译",
        text: binding(\.sentenceTranslation),
        axis: .vertical
      )

      HStack {
        Label("修改会自动保存到本次草稿", systemImage: "checkmark.circle")
          .font(.caption)
          .foregroundStyle(.tertiary)
        Spacer()
        Button {
          Task {
            await shell.addCurrentDraftToLearning()
            if shell.translationDraft == nil {
              onDismiss()
            }
          }
        } label: {
          Label("加入学习", systemImage: "plus")
            .font(.body.weight(.semibold))
            .foregroundStyle(isAddToLearningDisabled ? .black : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(.capsule)
        }
        .adaptiveTintedGlassButton()
        .disabled(isAddToLearningDisabled)
      }
    }
    .padding(4)
  }

  private var isAddToLearningDisabled: Bool {
    shell.translationDraft?.canonicalForm
      .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
  }

  private func binding(_ keyPath: WritableKeyPath<TranslationDraft, String>) -> Binding<String> {
    Binding(
      get: {
        shell.translationDraft?[keyPath: keyPath] ?? ""
      },
      set: { value in
        guard var draft = shell.translationDraft else {
          return
        }
        draft[keyPath: keyPath] = value
        shell.translationDraft = draft
      }
    )
  }

  private var pendingMergeBinding: Binding<Bool> {
    Binding(
      get: { shell.pendingLearningMerge != nil },
      set: { _ in }
    )
  }

  private var learningAdditionErrorBinding: Binding<Bool> {
    Binding(
      get: { shell.learningAdditionErrorMessage != nil },
      set: { isPresented in
        if !isPresented {
          shell.clearLearningAdditionError()
        }
      }
    )
  }
}

private struct ContentFittingHeight: ViewModifier {
  let enabled: Bool

  @ViewBuilder
  func body(content: Content) -> some View {
    if enabled {
      content.fixedSize(horizontal: false, vertical: true)
    } else {
      content
    }
  }
}

private struct DraftField: View {
  let title: String
  @Binding var text: String
  var axis: Axis = .horizontal

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(LocalizedStringKey(title))
        .font(.caption)
        .foregroundStyle(.secondary)
      if axis == .vertical {
        TextField(LocalizedStringKey(title), text: $text, axis: axis)
          .lineLimit(2...)
      } else {
        TextField(LocalizedStringKey(title), text: $text, axis: axis)
          .lineLimit(1)
      }
    }
  }
}

#if DEBUG
  #Preview("翻译浮窗") {
    PreviewFactory.translationPanelView()
  }

  #Preview("翻译字段") {
    DraftField(
      title: "语境释义",
      text: .constant("意外发现美好事物的幸运"),
      axis: .vertical
    )
    .padding()
    .frame(width: 360)
  }
#endif
