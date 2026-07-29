import Foundation
import Testing

@testable import TranStudy

struct DailyReviewQueueBuilderTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  @Test("overdue days stay oldest-first while equal-day cards use a reproducible seed")
  func queueOrdersOverdueDaysAndReproducesSeededTies() {
    let reviewDate = date(year: 2026, month: 7, day: 10)
    let oldest = item("oldest", dueAt: date(year: 2026, month: 7, day: 7))
    let newest = item("newest", dueAt: date(year: 2026, month: 7, day: 9))
    let tied = [
      item("alpha", dueAt: date(year: 2026, month: 7, day: 8)),
      item("bravo", dueAt: date(year: 2026, month: 7, day: 8)),
      item("charlie", dueAt: date(year: 2026, month: 7, day: 8)),
      item("delta", dueAt: date(year: 2026, month: 7, day: 8)),
    ]
    let builder = DailyReviewQueueBuilder(calendar: calendar)

    let first = builder.makeQueue(
      from: [newest] + tied + [oldest],
      at: reviewDate,
      seed: 42
    )
    let repeated = builder.makeQueue(
      from: [newest] + tied + [oldest],
      at: reviewDate,
      seed: 42
    )
    let anotherSeed = builder.makeQueue(
      from: [newest] + tied + [oldest],
      at: reviewDate,
      seed: 84
    )

    #expect(first.items.first == oldest)
    #expect(first.items.last == newest)
    #expect(Set(first.items[1...4].map(\.id)) == Set(tied.map(\.id)))
    #expect(first.items == repeated.items)
    #expect(first.items != anotherSeed.items)
  }

  @Test("related word and sentence cards are separated when another card is available")
  func queueSeparatesRelatedCards() {
    let dueAt = date(year: 2026, month: 7, day: 8)
    let word = item("run", dueAt: dueAt)
    let sentence = item(
      "I run every morning.",
      kind: .sentence,
      dueAt: dueAt
    )
    let unrelated = item("ocean", dueAt: dueAt)
    let queue = DailyReviewQueueBuilder(calendar: calendar).makeQueue(
      from: [word, sentence, unrelated],
      at: date(year: 2026, month: 7, day: 10),
      seed: 7
    )

    let wordIndex = queue.items.firstIndex(of: word)
    let sentenceIndex = queue.items.firstIndex(of: sentence)

    #expect(wordIndex != nil)
    #expect(sentenceIndex != nil)
    #expect(abs((wordIndex ?? 0) - (sentenceIndex ?? 0)) == 2)
    #expect(Set(queue.items.map(\.kind)) == [.word, .sentence])
  }

  @Test("all due cards are retained in batches of at most twenty")
  func queueRetainsAllCardsInTwentyCardBatches() {
    let dueAt = date(year: 2026, month: 7, day: 8)
    let items = (0..<45).map {
      item("word-\($0)", dueAt: dueAt)
    }

    let queue = DailyReviewQueueBuilder(calendar: calendar).makeQueue(
      from: items,
      at: date(year: 2026, month: 7, day: 10),
      seed: 12
    )

    #expect(queue.items.count == 45)
    #expect(queue.batches.map(\.count) == [20, 20, 5])
    #expect(Set(queue.items.map(\.id)) == Set(items.map(\.id)))
  }

  private func item(
    _ text: String,
    kind: LearningContentKind = .word,
    dueAt: Date
  ) -> LearningItem {
    LearningItem(
      id: UUID(),
      kind: kind,
      sourceText: text,
      canonicalForm: text,
      pronunciation: "",
      partOfSpeech: "",
      contextualMeaning: text,
      exampleSentence: kind == .word ? "\(text) example" : text,
      sentenceTranslation: "\(text) translation",
      sourceApplicationName: "Test",
      createdAt: dueAt.addingTimeInterval(-86_400),
      nextReviewAt: dueAt
    )
  }

  private func date(year: Int, month: Int, day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
  }
}
