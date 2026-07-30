protocol PreparationStateStoring {
  func loadHasCompletedInitialFlow() -> Bool
  func saveHasCompletedInitialFlow(_ hasCompleted: Bool)
}
