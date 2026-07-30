<p align="center">
  <img src="./artwork/transtudy-poster-wide.png" alt="TranStudy — A word returns" width="100%">
</p>

<h1 align="center">TranStudy</h1>

<p align="center">
  在真实语境中遇见，在恰当时间再次记住。<br>
  Meet words in context. Remember them when the time is right.
</p>

<p align="center">
  <a href="#中文">中文</a> · <a href="#english">English</a>
</p>

## 中文

TranStudy 是一款原生 macOS 语境翻译与间隔复习应用。它把你在阅读中遇到的单词、短语和句子，从一次临时翻译变成可以持续积累和复习的学习内容。

### 下载与安装

前往 [GitHub Releases](https://github.com/cynicalight/TranStudy/releases)，在最新版本的 Assets 中下载以 `.dmg` 结尾的安装包。打开 DMG 后，将 TranStudy 拖入“应用程序”文件夹，然后从“应用程序”中启动。TranStudy 需要 macOS 14 或更高版本。

首次启动时，应用会引导你配置划词所需的辅助功能权限、翻译服务和可选的复习通知。你可以使用 DeepSeek，或填写自定义地址和模型来连接 OpenAI 兼容接口。

### 两种划词翻译方式

在支持直接划词的应用中，用鼠标选中单词、短语或句子后，TranStudy 会在选区旁显示轻量的翻译图标。点击图标后，应用才会读取选区和必要的上下文并请求翻译。

如果当前应用或内容无法显示翻译图标，先复制需要翻译的文字，再按默认全局快捷键 F5，即可强制翻译剪贴板内容。你可以在设置中修改这个快捷键，也可以在应用内翻译长文本。

### 不只翻译单词，也保留遇见它的语境

划词翻译不会把选中的生词孤立处理：TranStudy 会自动识别它所在的完整句子，并在可用时带上前后句作为翻译上下文。选择“加入学习”后，应用会保留你当时看到的原始句子及其译文，作为该生词的真实遇见记录，方便你在之后的复习中回到当时的语境。

### 从翻译到学习

翻译结果不会自动进入单词库。确认释义、发音和例句后，你可以选择“加入学习”，保留真实遇词语境。单词库支持搜索、编辑、自定义例句、归档、暂停复习和删除撤销。

### 在恰当时间复习

TranStudy 根据学习记录安排每日复习。卡片会先邀请你回忆，再通过“忘记”“困难”“记得”或“简单”记录记忆状态并调整之后的复习节奏。只有存在到期内容时，应用才会发送复习提醒。

### 隐私

API 密钥保存在 macOS 钥匙串中，学习记录保存在这台 Mac 上。TranStudy 只会把你明确请求翻译的文字发送给当前选择的翻译服务，不会在请求失败后自动转发给其他服务。密码框、受保护内容和无法确认安全属性的输入区域不会显示划词翻译入口。

### 从源码构建

源码构建需要 Xcode 26 或更高版本。只有在修改 `project.yml` 后重新生成 Xcode 工程时，才需要额外安装 XcodeGen 2.45 或更高版本。

```sh
xcodegen generate

xcodebuild build \
  -project TranStudy.xcodeproj \
  -scheme TranStudy \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

运行完整测试：

```sh
xcodebuild test \
  -project TranStudy.xcodeproj \
  -scheme TranStudy \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

## English

TranStudy is a native macOS app for contextual translation and spaced-repetition learning. It turns words, phrases, and sentences encountered while reading from one-off translations into learning material you can retain and revisit.

### Download and install

Visit [GitHub Releases](https://github.com/cynicalight/TranStudy/releases) and download the `.dmg` file from the Assets section of the latest release. Open the DMG, drag TranStudy into the Applications folder, and launch it from Applications. TranStudy requires macOS 14 or later.

On first launch, TranStudy guides you through the Accessibility permission used for selection translation, translation-service configuration, and optional review notifications. You can use DeepSeek or connect to an OpenAI-compatible endpoint with a custom base URL and model.

### Two ways to translate selected text

In apps that support direct selection translation, select a word, phrase, or sentence with the mouse and TranStudy shows a lightweight translation icon beside it. The app reads the selection and necessary context only after you click that icon.

If the icon cannot appear in the current app or content, copy the text you want to translate and press the default global shortcut, F5, to force a translation of the clipboard. You can change this shortcut in Settings or translate longer passages inside the app.

### More than a definition: retain the context in which you met a word

TranStudy does not treat a selected word in isolation. It identifies the complete sentence containing it and, when available, includes the surrounding sentences as translation context. When you choose “Add to Learning,” the original sentence you saw and its translation are retained as a real encounter record for that word, so later reviews can bring you back to that context.

### Turn translations into learning

Translation results are never added to your library automatically. After reviewing the meaning, pronunciation, and examples, choose “Add to Learning” to preserve the real context in which you encountered the text. The library supports search, editing, custom examples, archiving, pausing reviews, and undoable deletion.

### Review at the right time

TranStudy schedules daily reviews from your learning history. Each card asks you to recall the answer before rating it as “Forgot,” “Hard,” “Remembered,” or “Easy,” then adjusts the future review rhythm. Review notifications are sent only when content is due.

### Privacy

API keys are stored in the macOS Keychain, and learning records remain on this Mac. TranStudy sends only text you explicitly ask to translate to the currently selected provider and never forwards it to another provider after a failure. Password fields, protected content, and inputs whose security cannot be verified never show the selection-translation entry point.

### Build from source

Building from source requires Xcode 26 or later. XcodeGen 2.45 or later is needed only when regenerating the Xcode project after changing `project.yml`.

```sh
xcodegen generate

xcodebuild build \
  -project TranStudy.xcodeproj \
  -scheme TranStudy \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

Run the full test suite:

```sh
xcodebuild test \
  -project TranStudy.xcodeproj \
  -scheme TranStudy \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```
