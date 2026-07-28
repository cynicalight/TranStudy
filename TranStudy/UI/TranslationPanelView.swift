import SwiftUI

struct TranslationPanelView: View {
  @Bindable var shell: ApplicationShell
  let onDismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text(shell.translationSourceText.isEmpty ? "翻译" : shell.translationSourceText)
          .font(.title2.weight(.semibold))
        Spacer()
        Button {
          onDismiss()
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("关闭")
      }

      content
    }
    .padding(20)
    .frame(width: 460)
    .onExitCommand(perform: onDismiss)
  }

  @ViewBuilder
  private var content: some View {
    switch shell.translationStatus {
    case .idle, .loading:
      HStack(spacing: 10) {
        ProgressView()
          .controlSize(.small)
        Text("正在翻译…")
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, minHeight: 160)
    case .failed:
      ContentUnavailableView(
        "翻译失败",
        systemImage: "exclamationmark.triangle",
        description: Text("请检查翻译服务设置和网络，然后重试。")
      )
    case .ready:
      if shell.translationDraft != nil {
        draftForm
      }
    }
  }

  private var draftForm: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        TextField("规范词形", text: binding(\.canonicalForm))
          .font(.title3.weight(.semibold))
        TextField("音标", text: binding(\.pronunciation))
          .frame(width: 130)
      }

      HStack {
        TextField("词性", text: binding(\.partOfSpeech))
          .frame(width: 100)
        TextField("语境释义", text: binding(\.contextualMeaning))
      }

      TextField("英文例句", text: binding(\.exampleSentence), axis: .vertical)
        .lineLimit(2...4)
      TextField("整句翻译", text: binding(\.sentenceTranslation), axis: .vertical)
        .lineLimit(2...4)

      HStack {
        Text("修改会自动保存在本次运行草稿中")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("加入学习") {
          Task {
            await shell.addCurrentDraftToLearning()
            if shell.translationDraft == nil {
              onDismiss()
            }
          }
        }
        .buttonStyle(.borderedProminent)
      }
    }
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
