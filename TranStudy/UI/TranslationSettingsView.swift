import AppKit
import SwiftUI

struct TranslationSettingsView: View {
  let shell: ApplicationShell

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
          Toggle(
            "登录时启动",
            isOn: Binding(
              get: { shell.isLaunchAtLoginEnabled },
              set: { shell.setLaunchAtLoginEnabled($0) }
            )
          )

          Toggle(
            "每日复习提醒",
            isOn: Binding(
              get: { shell.reviewReminderConfiguration.isEnabled },
              set: { isEnabled in
                Task {
                  await shell.setReviewReminderEnabled(isEnabled)
                }
              }
            )
          )

          DatePicker(
            "提醒时间",
            selection: reminderTime,
            displayedComponents: .hourAndMinute
          )
          .disabled(!shell.reviewReminderConfiguration.isEnabled)
        } header: {
          Label("启动与提醒", systemImage: "bell.badge")
        } footer: {
          Text("仅在存在到期卡片时提醒；通知权限被拒绝不会影响翻译与学习。")
        }

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
            "允许加入句子卡",
            isOn: Binding(
              get: { shell.isSentenceCardsEnabled },
              set: { shell.setSentenceCardsEnabled($0) }
            )
          )
        } header: {
          Label("句子卡", systemImage: "text.quote")
        } footer: {
          Text("开启后，长文本结果会显示“加入所在句”。翻译成功本身不会自动保存。")
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
          TranslationServiceSetupView(shell: shell)
        } header: {
          Label("翻译服务", systemImage: "network")
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
      }
      .formStyle(.grouped)
      .frame(maxWidth: TranStudyDesign.pageWidth)
      .padding(.horizontal, 16)
    }
  }

  private var reminderTime: Binding<Date> {
    Binding(
      get: {
        var components = Calendar.autoupdatingCurrent.dateComponents(
          [.year, .month, .day],
          from: Date()
        )
        components.hour = shell.reviewReminderConfiguration.hour
        components.minute = shell.reviewReminderConfiguration.minute
        return Calendar.autoupdatingCurrent.date(from: components) ?? Date()
      },
      set: { date in
        let components = Calendar.autoupdatingCurrent.dateComponents(
          [.hour, .minute],
          from: date
        )
        Task {
          await shell.setReviewReminderTime(
            hour: components.hour ?? 9,
            minute: components.minute ?? 0
          )
        }
      }
    )
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
