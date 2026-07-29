struct TranslationDraft: Equatable, Sendable {
  var sourceText: String
  var canonicalForm: String
  var pronunciation: String
  var partOfSpeech: String
  var contextualMeaning: String
  var exampleSentence: String
  var sentenceTranslation: String

  init(result: TranslationResult) {
    self.init(
      sourceText: result.sourceText,
      canonicalForm: result.canonicalForm,
      pronunciation: result.pronunciation,
      partOfSpeech: result.partOfSpeech,
      contextualMeaning: result.contextualMeaning,
      exampleSentence: result.exampleSentence,
      sentenceTranslation: result.sentenceTranslation
    )
  }

  init(
    sourceText: String,
    canonicalForm: String,
    pronunciation: String,
    partOfSpeech: String,
    contextualMeaning: String,
    exampleSentence: String,
    sentenceTranslation: String
  ) {
    self.sourceText = sourceText
    self.canonicalForm = canonicalForm
    self.pronunciation = pronunciation
    self.partOfSpeech = partOfSpeech
    self.contextualMeaning = contextualMeaning
    self.exampleSentence = TranslationTextNormalizer.collapseWhitespace(in: exampleSentence)
    self.sentenceTranslation = TranslationTextNormalizer.collapseWhitespace(in: sentenceTranslation)
  }
}
