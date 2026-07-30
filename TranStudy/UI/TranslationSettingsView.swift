import AppKit
import SwiftUI

struct TranslationSettingsView: View {
  private struct PreparedExport {
    let document: JSONFileDocument
    let filename: String
  }

  let shell: ApplicationShell
  @State private var isImportingLearningData = false
  @State private var isPreparingExport = false
  @State private var preparedExport: PreparedExport?
  @State private var isConfirmingLearningDataClear = false
  @State private var learningDataClearConfirmation = ""
  @State private var dataOperationMessage: String?

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
          Picker(
            "界面语言",
            selection: Binding(
              get: { shell.interfaceLanguage },
              set: { shell.setInterfaceLanguage($0) }
            )
          ) {
            ForEach(InterfaceLanguage.allCases) { language in
              Text(language.localizedTitle)
                .tag(language)
            }
          }

          Picker(
            "中文输出",
            selection: Binding(
              get: { shell.chineseWritingSystem },
              set: { shell.setChineseWritingSystem($0) }
            )
          ) {
            ForEach(ChineseWritingSystem.allCases) { writingSystem in
              Text(writingSystem.localizedTitle)
                .tag(writingSystem)
            }
          }
        } header: {
          Label("语言与翻译", systemImage: "globe")
        } footer: {
          Text("中文书写形式只影响之后的新翻译，不会改写已有学习记录。")
        }

        Section {
          Picker(
            "英语语音",
            selection: Binding(
              get: { shell.languageAndSpeechPreferences.speechVoiceIdentifier },
              set: { shell.setSpeechVoiceIdentifier($0) }
            )
          ) {
            Text("系统默认英语语音")
              .tag(String?.none)
            ForEach(shell.availableSpeechVoices) { voice in
              Text("\(voice.name)（\(voice.language)）")
                .tag(Optional(voice.identifier))
            }
          }

          HStack {
            Text("语速")
            Slider(
              value: Binding(
                get: { Double(shell.languageAndSpeechPreferences.speechRate) },
                set: { shell.setSpeechRate(Float($0)) }
              ),
              in: 0.35...0.65,
              step: 0.05
            )
            Text(
              shell.languageAndSpeechPreferences.speechRate,
              format: .number.precision(.fractionLength(2))
            )
            .monospacedDigit()
          }

          Toggle(
            "翻译完成后自动朗读英文",
            isOn: Binding(
              get: {
                shell.languageAndSpeechPreferences.automaticallySpeaksTranslations
              },
              set: { shell.setAutomaticallySpeaksTranslations($0) }
            )
          )

          Button {
            shell.speak("TranStudy helps you learn from context.")
          } label: {
            Label("试听语音", systemImage: "speaker.wave.2")
          }
        } header: {
          Label("发音", systemImage: "waveform")
        } footer: {
          Text("自动朗读默认关闭；单词和例句旁的朗读按钮始终可以手动使用。")
        }

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
                Button(
                  application.localizedName
                    ?? application.bundleIdentifier
                    ?? shell.localized("未知应用")
                ) {
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
              label: { shell.localized($0.title) }
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

        Section {
          LazyVGrid(
            columns: [
              GridItem(.flexible(), spacing: 12),
              GridItem(.flexible(), spacing: 12),
            ],
            spacing: 12
          ) {
            Button {
              isPreparingExport = true
              dataOperationMessage = shell.localized("正在准备学习数据…")
              Task {
                await Task.yield()
                defer {
                  isPreparingExport = false
                }
                do {
                  preparedExport = PreparedExport(
                    document: JSONFileDocument(data: try await shell.makeLearningDataExport()),
                    filename: "TranStudy-learning-data"
                  )
                } catch {
                  dataOperationMessage = shell.localized("无法导出学习数据。")
                }
              }
            } label: {
              Label("导出学习数据", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isPreparingExport)

            Button {
              isImportingLearningData = true
            } label: {
              Label("导入学习数据", systemImage: "square.and.arrow.down")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
              do {
                try shell.clearTranslationCache()
                dataOperationMessage = shell.localized("翻译缓存已清理。")
              } catch {
                dataOperationMessage = shell.localized("无法清理翻译缓存。")
              }
            } label: {
              Label("清理翻译缓存", systemImage: "arrow.triangle.2.circlepath")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
              do {
                preparedExport = PreparedExport(
                  document: JSONFileDocument(data: try shell.makeDiagnosticExport()),
                  filename: "TranStudy-diagnostics"
                )
              } catch {
                dataOperationMessage = shell.localized("无法导出诊断日志。")
              }
            } label: {
              Label("导出诊断日志", systemImage: "stethoscope")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isPreparingExport)

            Button(role: .destructive) {
              learningDataClearConfirmation = ""
              isConfirmingLearningDataClear = true
            } label: {
              Label("清除所有学习数据", systemImage: "trash")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            Color.clear
              .accessibilityHidden(true)
          }

          if let dataOperationMessage {
            Text(dataOperationMessage)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        } header: {
          Label("数据与隐私", systemImage: "externaldrive")
        } footer: {
          Text(
            LocalizedStringKey(
              "学习数据导出不包含 API 密钥、翻译缓存或设备设置。"
                + "诊断日志只在你主动导出时生成文件，不包含划词内容、上下文、例句、密钥或模型原始响应。"
                + "TranStudy 不使用第三方分析或自动崩溃上报。"
            )
          )
        }
      }
      .formStyle(.grouped)
      .scrollIndicators(.hidden)
      .frame(maxWidth: TranStudyDesign.pageWidth)
      .padding(.horizontal, 16)
    }
    .fileImporter(
      isPresented: $isImportingLearningData,
      allowedContentTypes: [.json],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else {
        if case .failure = result {
          dataOperationMessage = shell.localized("无法读取学习数据文件。")
        }
        return
      }
      Task {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
          if didAccess {
            url.stopAccessingSecurityScopedResource()
          }
        }
        do {
          let summary = try await shell.importLearningData(Data(contentsOf: url))
          dataOperationMessage = shell.localizedFormat(
            "导入完成：新增 %d 条，合并 %d 条。",
            summary.importedItemCount,
            summary.mergedItemCount
          )
        } catch {
          dataOperationMessage = shell.localized("无法导入学习数据，请确认文件格式。")
        }
      }
    }
    .fileExporter(
      isPresented: isExportingPreparedData,
      document: preparedExport?.document ?? JSONFileDocument(),
      contentType: .json,
      defaultFilename: preparedExport?.filename ?? "TranStudy-data"
    ) { result in
      switch result {
      case .success:
        dataOperationMessage = shell.localized("数据文件已导出。")
      case .failure:
        dataOperationMessage = shell.localized("无法保存数据文件。")
      }
    }
    .alert("清除所有学习数据", isPresented: $isConfirmingLearningDataClear) {
      TextField("输入 DELETE", text: $learningDataClearConfirmation)
      Button("取消", role: .cancel) {}
      Button("永久清除", role: .destructive) {
        Task {
          do {
            try await shell.clearAllLearningData()
            dataOperationMessage = shell.localized("所有学习数据已清除。")
          } catch {
            dataOperationMessage = shell.localized("无法清除学习数据。")
          }
        }
      }
      .disabled(learningDataClearConfirmation != "DELETE")
    } message: {
      Text("此操作无法撤销。请输入 DELETE 以确认。翻译缓存不会随学习数据一起清除。")
    }
  }

  private var isExportingPreparedData: Binding<Bool> {
    Binding(
      get: {
        preparedExport != nil
      },
      set: { isPresented in
        if !isPresented {
          preparedExport = nil
        }
      }
    )
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
      Label(LocalizedStringKey(detail), systemImage: "checkmark.circle.fill")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }

}

extension InterfaceLanguage {
  fileprivate var localizedTitle: LocalizedStringKey {
    switch self {
    case .system:
      "跟随 macOS"
    case .simplifiedChinese:
      "简体中文"
    case .traditionalChinese:
      "繁體中文"
    case .english:
      "English"
    }
  }
}

extension ChineseWritingSystem {
  fileprivate var localizedTitle: LocalizedStringKey {
    switch self {
    case .simplified:
      "简体中文"
    case .traditional:
      "繁體中文"
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
