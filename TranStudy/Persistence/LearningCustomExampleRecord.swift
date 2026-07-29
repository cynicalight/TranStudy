import Foundation
import SwiftData

@Model
final class LearningCustomExampleRecord {
  @Attribute(.unique) var id: UUID
  var englishText: String = ""
  var chineseTranslation: String = ""
  var sortOrder: Int = 0
  var learningRecord: LearningRecord?

  init(
    id: UUID = UUID(),
    englishText: String,
    chineseTranslation: String,
    sortOrder: Int = 0
  ) {
    self.id = id
    self.englishText = englishText
    self.chineseTranslation = chineseTranslation
    self.sortOrder = sortOrder
  }
}
