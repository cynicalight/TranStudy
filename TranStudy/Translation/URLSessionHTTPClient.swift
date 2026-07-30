import Foundation

@MainActor
final class URLSessionHTTPClient: HTTPDataLoading {
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw TranslationError.invalidResponse(.malformedPayload)
    }

    return (data, httpResponse)
  }
}
