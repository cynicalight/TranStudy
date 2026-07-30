struct SpeechVoice: Equatable, Identifiable, Sendable {
  let identifier: String
  let name: String
  let language: String

  var id: String {
    identifier
  }
}

@MainActor
protocol SpeechPlaying {
  var availableVoices: [SpeechVoice] { get }
  func speak(_ text: String)
  func speak(
    _ text: String,
    voiceIdentifier: String?,
    rate: Float
  )
  func stop()
}

extension SpeechPlaying {
  var availableVoices: [SpeechVoice] {
    []
  }

  func speak(
    _ text: String,
    voiceIdentifier: String?,
    rate: Float
  ) {
    speak(text)
  }

  func stop() {}
}
