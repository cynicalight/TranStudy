enum AppDestination: String, CaseIterable, Equatable, Identifiable {
  case todayReview
  case library
  case settings

  var id: Self {
    self
  }

  var title: String {
    switch self {
    case .todayReview:
      "今日复习"
    case .library:
      "单词库"
    case .settings:
      "设置"
    }
  }

  var systemImage: String {
    switch self {
    case .todayReview:
      "rectangle.stack"
    case .library:
      "books.vertical"
    case .settings:
      "gearshape"
    }
  }

  var placeholderDescription: String {
    switch self {
    case .todayReview:
      "到期的学习内容会显示在这里。"
    case .library:
      "加入学习的单词和句子会显示在这里。"
    case .settings:
      "划词、翻译服务和提醒设置会显示在这里。"
    }
  }
}
