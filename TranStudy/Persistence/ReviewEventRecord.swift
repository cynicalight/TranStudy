import Foundation
import SwiftData

@Model
final class ReviewEventRecord {
  @Attribute(.unique) var id: UUID
  var ratingRawValue: String = ""
  var reviewedAt: Date = Date()
  var previousReviewAt: Date?
  var nextReviewAt: Date = Date()
  var intervalDays: Double = 1
  var learningRecord: LearningRecord?

  init(
    id: UUID = UUID(),
    rating: ReviewRating,
    reviewedAt: Date,
    previousReviewAt: Date?,
    nextReviewAt: Date,
    intervalDays: Double
  ) {
    self.id = id
    ratingRawValue = rating.rawValue
    self.reviewedAt = reviewedAt
    self.previousReviewAt = previousReviewAt
    self.nextReviewAt = nextReviewAt
    self.intervalDays = intervalDays
  }
}
