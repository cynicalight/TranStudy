import Foundation

struct DailyReviewQueue: Equatable, Sendable {
  static let batchSize = 20

  let items: [LearningItem]

  var batches: [[LearningItem]] {
    stride(from: 0, to: items.count, by: Self.batchSize).map { startIndex in
      Array(items[startIndex..<min(startIndex + Self.batchSize, items.count)])
    }
  }
}

struct DailyReviewQueueBuilder {
  let calendar: Calendar

  init(calendar: Calendar = .autoupdatingCurrent) {
    self.calendar = calendar
  }

  func makeQueue(
    from items: [LearningItem],
    at reviewDate: Date,
    seed: UInt64
  ) -> DailyReviewQueue {
    let dueItems = items.filter {
      !$0.isPaused && ($0.nextReviewAt ?? .distantFuture) <= reviewDate
    }
    let groups = Dictionary(grouping: dueItems) {
      calendar.startOfDay(for: $0.nextReviewAt ?? reviewDate)
    }
    var generator = SeededRandomNumberGenerator(seed: seed)
    let orderedItems = groups.keys.sorted().flatMap { dueDay in
      var shuffledItems = groups[dueDay, default: []]
      shuffledItems.shuffle(using: &generator)
      return spaceRelatedItems(shuffledItems)
    }
    return DailyReviewQueue(items: orderedItems)
  }

  static func seed(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> UInt64 {
    let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
    let era = UInt64(components.era ?? 0)
    let year = UInt64(components.year ?? 0)
    let month = UInt64(components.month ?? 0)
    let day = UInt64(components.day ?? 0)
    return (era << 48) ^ (year << 16) ^ (month << 8) ^ day
  }

  private func spaceRelatedItems(_ shuffledItems: [LearningItem]) -> [LearningItem] {
    var remainingItems = shuffledItems
    var orderedItems: [LearningItem] = []

    while !remainingItems.isEmpty {
      let previousTokens = orderedItems.last.map(relatedTokens(for:)) ?? []
      let separatedCandidates = remainingItems.indices.filter {
        previousTokens.isDisjoint(with: relatedTokens(for: remainingItems[$0]))
      }
      let candidateIndices =
        separatedCandidates.isEmpty
        ? Array(remainingItems.indices)
        : separatedCandidates
      let selectedIndex =
        candidateIndices.max {
          relationCount(for: remainingItems[$0], among: remainingItems)
            < relationCount(for: remainingItems[$1], among: remainingItems)
        } ?? remainingItems.startIndex
      orderedItems.append(remainingItems.remove(at: selectedIndex))
    }
    return orderedItems
  }

  private func relationCount(
    for item: LearningItem,
    among items: [LearningItem]
  ) -> Int {
    let tokens = relatedTokens(for: item)
    return items.count {
      $0.id != item.id && !tokens.isDisjoint(with: relatedTokens(for: $0))
    }
  }

  private func relatedTokens(for item: LearningItem) -> Set<String> {
    let text =
      item.kind == .word
      ? item.canonicalForm
      : item.sourceText
    return Set(
      text.lowercased().split {
        !$0.isLetter && !$0.isNumber
      }.map(String.init)
    )
  }
}

private struct SeededRandomNumberGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }
}
