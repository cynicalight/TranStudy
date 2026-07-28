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

      Section("翻译服务") {
        Picker(
          "供应商",
          selection: Binding(
            get: {
              shell.translationProviderConfiguration.provider
            },
            set: {
              shell.selectTranslationProvider($0)
              apiKey = ""
            }
          )
        ) {
          ForEach(TranslationProviderKind.allCases) { provider in
            Text(provider.title)
              .tag(provider)
          }
        }
        .pickerStyle(.segmented)

        providerFields

        SecureField("API Key", text: $apiKey)
          .textContentType(.password)

        HStack {
          Button("测试连接") {
            Task {
              await shell.testTranslationConnection(apiKey: apiKey)
            }
          }
          .disabled(!canTestConnection)

          connectionStatus
        }
      }

      Section {
        Text("每个供应商的 API Key 只在连接成功后写入 macOS Keychain，不进入学习数据库。")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("设置")
    .padding()
  }

  @ViewBuilder
  private var providerFields: some View {
    switch shell.translationProviderConfiguration.provider {
    case .deepSeek:
      Picker(
        "模型",
        selection: Binding(
          get: {
            shell.translationProviderConfiguration.deepSeekModel
          },
          set: {
            shell.updateDeepSeekModel($0)
          }
        )
      ) {
        ForEach(DeepSeekModel.allCases) { model in
          Text(model.title)
            .tag(model)
        }
      }
    case .openAICompatible:
      TextField(
        "Base URL",
        text: Binding(
          get: {
            shell.translationProviderConfiguration.customBaseURL
          },
          set: {
            shell.updateCustomProvider(
              baseURL: $0,
              model: shell.translationProviderConfiguration.customModel
            )
          }
        )
      )
      TextField(
        "模型名称",
        text: Binding(
          get: {
            shell.translationProviderConfiguration.customModel
          },
          set: {
            shell.updateCustomProvider(
              baseURL: shell.translationProviderConfiguration.customBaseURL,
              model: $0
            )
          }
        )
      )
    }
  }

  private var canTestConnection: Bool {
    guard
      !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      shell.connectionStatus != .testing
    else {
      return false
    }

    switch shell.translationProviderConfiguration.provider {
    case .deepSeek:
      return true
    case .openAICompatible:
      return
        !shell.translationProviderConfiguration.customBaseURL
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !shell.translationProviderConfiguration.customModel
          .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
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
