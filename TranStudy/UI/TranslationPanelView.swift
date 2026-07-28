import SwiftUI

struct TranslationPanelView: View {
  @Bindable var shell: ApplicationShell
  let onDismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      panelHeader

      content
    }
    .padding(14)
    .frame(width: 500)
    .onExitCommand(perform: onDismiss)
  }

  private var panelHeader: some View {
    HStack(spacing: 11) {
      Image(systemName: "character.bubble.fill")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.tint)
        .frame(width: 32, height: 32)
        .background(.tint.opacity(0.1), in: .rect(cornerRadius: 9))

      VStack(alignment: .leading, spacing: 1) {
        Text("翻译剪贴板")
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
    case .failed:
      VStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 28))
          .foregroundStyle(.orange)
        Text("翻译失败")
          .font(.title3.weight(.semibold))
        Text("请检查翻译服务设置和网络，然后重试。")
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, minHeight: 220)
    case .ready:
      if shell.translationDraft != nil {
        draftForm
      }
    }
  }

  private var draftForm: some View {
    VStack(alignment: .leading, spacing: 14) {
      if !shell.translationSourceText.isEmpty {
        Text(shell.translationSourceText)
          .font(.title3.weight(.semibold))
          .lineLimit(2)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      Divider()

      HStack {
        DraftField(
          title: "规范词形",
          text: binding(\.canonicalForm)
        )
        DraftField(
          title: "音标",
          text: binding(\.pronunciation)
        )
        .frame(width: 150)
      }

      HStack {
        DraftField(
          title: "词性",
          text: binding(\.partOfSpeech)
        )
        .frame(width: 110)
        DraftField(
          title: "语境释义",
          text: binding(\.contextualMeaning)
        )
      }

      DraftField(
        title: "英文例句",
        text: binding(\.exampleSentence),
        axis: .vertical
      )

      DraftField(
        title: "整句翻译",
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
