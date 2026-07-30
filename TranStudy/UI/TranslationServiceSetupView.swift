import SwiftUI

struct TranslationServiceSetupView: View {
  let shell: ApplicationShell
  @State private var apiKey = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      CenteredLabeledContent("供应商") {
        TranStudySegmentedControl(
          options: TranslationProviderKind.allCases,
          selection: Binding(
            get: { shell.translationProviderConfiguration.provider },
            set: {
              shell.selectTranslationProvider($0)
              apiKey = ""
            }
          ),
          label: \.title
        )
        .frame(maxWidth: 420)
      }

      providerFields

      CenteredLabeledContent("API Key") {
        HStack(spacing: 10) {
          SecureField("API Key", text: $apiKey)
            .textFieldStyle(.roundedBorder)
            .textContentType(.password)

          Button {
            Task {
              await shell.testTranslationConnection(apiKey: apiKey)
            }
          } label: {
            Label("测试", systemImage: "bolt.horizontal.circle")
          }
          .buttonStyle(.borderedProminent)
          .disabled(!canTestConnection)

          connectionStatus
        }
      }

      Label(
        "连接成功后才会写入 macOS Keychain，不会进入学习数据库、缓存或日志。",
        systemImage: "lock.shield"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var providerFields: some View {
    switch shell.translationProviderConfiguration.provider {
    case .deepSeek:
      CenteredLabeledContent("模型") {
        Picker(
          "模型",
          selection: Binding(
            get: { shell.translationProviderConfiguration.deepSeekModel },
            set: { shell.updateDeepSeekModel($0) }
          )
        ) {
          ForEach(DeepSeekModel.allCases) { model in
            Text(model.title)
              .tag(model)
          }
        }
      }
    case .openAICompatible:
      CenteredLabeledContent("Base URL") {
        TextField(
          "Base URL",
          text: Binding(
            get: { shell.translationProviderConfiguration.customBaseURL },
            set: {
              shell.updateCustomProvider(
                baseURL: $0,
                model: shell.translationProviderConfiguration.customModel
              )
            }
          )
        )
        .textFieldStyle(.roundedBorder)
      }

      CenteredLabeledContent("模型名称") {
        TextField(
          "模型名称",
          text: Binding(
            get: { shell.translationProviderConfiguration.customModel },
            set: {
              shell.updateCustomProvider(
                baseURL: shell.translationProviderConfiguration.customBaseURL,
                model: $0
              )
            }
          )
        )
        .textFieldStyle(.roundedBorder)
      }
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
      if shell.isTranslationServiceConfigured {
        Label("当前供应商已配置", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
      }
    case .testing:
      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)
        Text("正在测试连接…")
      }
      .foregroundStyle(.secondary)
    case .connected:
      Label("连接成功，API Key 已安全保存", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .failed:
      Label("连接失败，请检查设置和网络", systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
    }
  }
}

struct CenteredLabeledContent<Content: View>: View {
  let title: String
  let content: Content

  init(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Text(title)
        .lineLimit(1)
        .frame(width: 96, alignment: .leading)

      content
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
  }
}
