import AppKit
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
          CenteredLabeledContent("翻译剪贴板") {
            Picker(
              "翻译剪贴板快捷键",
              selection: Binding(
                get: { shell.translationShortcut },
                set: { shell.setTranslationShortcut($0) }
              )
            ) {
              ForEach(TranslationShortcutKey.allCases) { shortcut in
                Text(shortcut.title)
                  .tag(shortcut)
              }
            }
            .labelsHidden()
            .frame(width: 140)
          }

          if case .failed(let shortcut) = shell.translationShortcutRegistrationStatus {
            Label(
              "无法注册 \(shortcut.title)，可能已被其他应用占用。",
              systemImage: "exclamationmark.triangle.fill"
            )
            .font(.callout)
            .foregroundStyle(.orange)
          }
        } header: {
          Label("快捷键", systemImage: "keyboard")
        } footer: {
          Text("默认使用 F5。修改后会立即更新全局快捷键。")
        }

        Section {
          Toggle(
            "启用全局划词",
            isOn: Binding(
              get: { shell.selectionConfiguration.isEnabled },
              set: { shell.setSelectionEnabled($0) }
            )
          )

          CenteredLabeledContent("排除应用") {
            Menu {
              ForEach(availableApplications, id: \.bundleIdentifier) { application in
                Button(application.localizedName ?? application.bundleIdentifier ?? "未知应用") {
                  guard let bundleIdentifier = application.bundleIdentifier else {
                    return
                  }
                  shell.excludeApplication(
                    bundleIdentifier: bundleIdentifier,
                    displayName: application.localizedName ?? bundleIdentifier
                  )
                }
              }
            } label: {
              Label("添加运行中的应用", systemImage: "plus")
            }
            .disabled(availableApplications.isEmpty)
          }

          ForEach(shell.selectionConfiguration.excludedApplications) { application in
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(application.displayName)
                Text(application.bundleIdentifier)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Button {
                shell.includeApplication(bundleIdentifier: application.bundleIdentifier)
              } label: {
                Image(systemName: "minus.circle")
              }
              .buttonStyle(.plain)
              .foregroundStyle(.secondary)
              .help("从排除列表移除")
              .accessibilityLabel("允许在 \(application.displayName) 中划词")
            }
          }
        } header: {
          Label("划词与隐私", systemImage: "hand.point.up.left.fill")
        } footer: {
          Text("密码框、受保护内容和无法确认安全属性的输入框始终不会显示翻译图标。")
        }

        Section {
          compatibilityRow("Safari", detail: "网页文字与上下文")
          compatibilityRow("Google Chrome", detail: "网页文字与上下文")
          compatibilityRow("TextEdit", detail: "纯文本与上下文")
          compatibilityRow("Preview", detail: "带文字层的 PDF；上下文尽力获取")
        } header: {
          Label("兼容性", systemImage: "checkmark.seal")
        } footer: {
          Text("图片、扫描 PDF 和其他不可访问文本不会尝试 OCR。其他应用按辅助功能信息尽力支持。")
        }

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

  private var availableApplications: [NSRunningApplication] {
    NSWorkspace.shared.runningApplications
      .filter { application in
        guard
          application.activationPolicy == .regular,
          let bundleIdentifier = application.bundleIdentifier,
          bundleIdentifier != Bundle.main.bundleIdentifier
        else {
          return false
        }
        return !shell.selectionConfiguration.excludes(bundleIdentifier: bundleIdentifier)
      }
      .sorted {
        ($0.localizedName ?? $0.bundleIdentifier ?? "")
          .localizedCaseInsensitiveCompare(
            $1.localizedName ?? $1.bundleIdentifier ?? ""
          ) == .orderedAscending
      }
  }

  private func compatibilityRow(_ application: String, detail: String) -> some View {
    HStack {
      Text(application)
      Spacer()
      Label(detail, systemImage: "checkmark.circle.fill")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
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
