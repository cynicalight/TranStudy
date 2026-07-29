import SwiftUI

struct TranslationPanelView: View {
  @Bindable var shell: ApplicationShell
  let onDismiss: () -> Void
  let onTranslateLongTextSelection: (NSRange) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      panelHeader

      if shell.isSelectionContextUnavailable {
        contextFallbackNotice
      }

      content
    }
    .padding(14)
    .frame(width: 500)
    .onExitCommand(perform: onDismiss)
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
        "“\(summary.incomingSourceText)”将合并到“\(summary.canonicalForm)”。"
          + "已有 \(summary.existingEncounterCount) 条语境会全部保留，并新增当前语境。"
      )
    }
  }

  private var contextFallbackNotice: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "info.circle.fill")
        .foregroundStyle(.orange)
      VStack(alignment: .leading, spacing: 3) {
        Text("当前应用无法取得完整上下文，本次仅根据目标词翻译。")
          .font(.callout.weight(.medium))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(.orange.opacity(0.08), in: .rect(cornerRadius: 10))
  }

  private var panelHeader: some View {
    HStack(spacing: 11) {
      Image(systemName: "character.bubble.fill")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.tint)
        .frame(width: 32, height: 32)
        .background(.tint.opacity(0.1), in: .rect(cornerRadius: 9))

      VStack(alignment: .leading, spacing: 1) {
        Text(shell.translationPresentationTitle)
          .font(.headline)
        Text("按 Esc 关闭")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Button {
        onDismiss()
      } label: {
        Image(systemName: "xmark")
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .contentShape(.rect)
      .help("关闭")
      .accessibilityLabel("关闭")
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
          shell.translationError == .inputTooLong
            ? "内容超过约 12000 字符或 token 预算，请缩短后重试。"
            : "请检查翻译服务设置和网络，然后重试。"
        )
        .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, minHeight: 220)
    case .ready:
      if let longTextTranslation = shell.longTextTranslation {
        LongTextTranslationView(
          shell: shell,
          result: longTextTranslation,
          onTranslateSelection: onTranslateLongTextSelection
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
      }
      .frame(height: 150)

      HStack(spacing: 10) {
        ProgressView()
          .controlSize(.small)
        Text("正在翻译完整内容…")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
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

      DraftField(
        title: "英文例句",
        text: binding(\.exampleSentence),
        axis: .vertical
      )

      DraftField(
        title: "例句中文翻译",
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
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          shell.translationDraft?.canonicalForm
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        )
      }
    }
    .padding(4)
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
}

private struct DraftField: View {
  let title: String
  @Binding var text: String
  var axis: Axis = .horizontal

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      TextField(title, text: $text, axis: axis)
        .lineLimit(axis == .vertical ? 2...4 : 1...1)
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
