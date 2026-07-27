import SwiftUI

struct TranslationSettingsView: View {
  let shell: ApplicationShell
  @State private var apiKey = ""

  var body: some View {
    Form {
      Section("悬浮窗") {
        Picker(
          "位置",
          selection: Binding(
            get: {
              shell.translationPanelPosition
            },
            set: {
              shell.setTranslationPanelPosition($0)
            }
          )
        ) {
          ForEach(TranslationPanelPosition.allCases) { position in
            Text(position.title)
              .tag(position)
          }
        }
        .pickerStyle(.segmented)
      }

      Section("DeepSeek") {
        LabeledContent("模型", value: DeepSeekModel.flash.title)
        SecureField("API Key", text: $apiKey)
          .textContentType(.password)

        HStack {
          Button("测试连接") {
            Task {
              await shell.testDeepSeekConnection(apiKey: apiKey)
            }
          }
          .disabled(
            apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || shell.connectionStatus == .testing
          )

          connectionStatus
        }
      }

      Section {
        Text("API Key 只在连接成功后写入 macOS Keychain，不进入学习数据库。")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("设置")
    .padding()
  }

  @ViewBuilder
  private var connectionStatus: some View {
    switch shell.connectionStatus {
    case .idle:
      EmptyView()
    case .testing:
      ProgressView()
        .controlSize(.small)
    case .connected:
      Label("连接成功", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .failed:
      Label("连接失败，请检查 API Key 和网络", systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
    }
  }
}
