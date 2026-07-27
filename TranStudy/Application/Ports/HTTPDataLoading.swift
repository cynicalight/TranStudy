import Foundation

@MainActor
protocol HTTPDataLoading {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
