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
}
