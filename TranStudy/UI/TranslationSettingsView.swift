import SwiftUI

struct TranslationSettingsView: View {
  let shell: ApplicationShell
  @State private var apiKey = ""

  var body: some View {
    VStack(spacing: 0) {
      PageHeader(
        title: "设置",
        subtitle: "调整翻译入口与服务连接，密钥始终保存在这台 Mac。",
        systemImage: "gearshape.fill"
      )
      .frame(maxWidth: TranStudyDesign.pageWidth, alignment: .leading)
      .padding(.horizontal, 32)
      .padding(.vertical, 24)

      Divider()

      Form {
        Section {
          CenteredLabeledContent("位置") {
            TranStudySegmentedControl(
              options: TranslationPanelPosition.allCases,
              selection: Binding(
                get: {
                  shell.translationPanelPosition
                },
                set: {
                  shell.setTranslationPanelPosition($0)
                }
              ),
              label: \.title
            )
            .frame(maxWidth: 420)
          }
        } header: {
          Label("悬浮窗", systemImage: "macwindow.on.rectangle")
        } footer: {
          Text("翻译浮窗会出现在当前屏幕的所选位置，并保持在其他应用上方。")
        }

        Section {
          CenteredLabeledContent("供应商") {
            TranStudySegmentedControl(
              options: TranslationProviderKind.allCases,
              selection: Binding(
                get: {
                  shell.translationProviderConfiguration.provider
                },
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
            HStack(spacing: 12) {
              SecureField(
                text: $apiKey,
                prompt: Text("输入后测试连接")
                  .foregroundStyle(.secondary)
              ) {
                Text("API Key")
              }
              .labelsHidden()
              .textFieldStyle(.roundedBorder)
              .multilineTextAlignment(.leading)
              .textContentType(.password)
              .frame(maxWidth: 360)

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
        } header: {
          Label("翻译服务", systemImage: "network")
        } footer: {
          Label(
            "连接成功后，API Key 才会写入 macOS Keychain；不会进入学习数据库、缓存或日志。",
            systemImage: "lock.shield"
          )
        }
      }
      .formStyle(.grouped)
      .frame(maxWidth: TranStudyDesign.pageWidth)
      .padding(.horizontal, 16)
    }
    .navigationTitle("设置")
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
      CenteredLabeledContent("Base URL") {
        TextField(
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
          ),
          prompt: Text("https://example.com/v1")
            .foregroundStyle(.secondary)
        ) {
          Text("Base URL")
        }
        .labelsHidden()
        .frame(maxWidth: 360)
      }

      CenteredLabeledContent("模型名称") {
        TextField(
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
          ),
          prompt: Text("例如 gpt-4.1-mini")
            .foregroundStyle(.secondary)
        ) {
          Text("模型名称")
        }
        .labelsHidden()
        .frame(maxWidth: 360)
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
      EmptyView()
    case .testing:
      ProgressView()
        .controlSize(.small)
    case .connected:
      Label("连接成功", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .font(.callout.weight(.medium))
    case .failed:
      Label("连接失败，请检查设置和网络", systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
        .font(.callout.weight(.medium))
    }
  }
}

private struct CenteredLabeledContent<Content: View>: View {
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

#if DEBUG
  #Preview("DeepSeek 设置") {
    PreviewFactory.translationSettingsView()
  }

  #Preview("OpenAI 兼容设置") {
    PreviewFactory.translationSettingsView(
      providerConfiguration: TranslationProviderConfiguration(
        provider: .openAICompatible,
        deepSeekModel: .flash,
        customBaseURL: "https://api.example.com/v1",
        customModel: "gpt-4.1-mini"
      )
    )
  }
#endif
