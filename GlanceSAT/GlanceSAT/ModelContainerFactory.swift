//
//  ModelContainerFactory.swift
//  GlanceSAT
//

import Foundation
import SwiftData

enum ModelContainerFactory {
  private static let modelTypes: [any PersistentModel.Type] = [
    Item.self,
    Word.self,
    QuizSession.self,
  ]

  static func makeShared() throws -> ModelContainer {
    let schema = Schema(modelTypes)
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

    do {
      return try ModelContainer(for: schema, configurations: [configuration])
    } catch {
      // Simulator / dev: existing store may predate `QuizSession.calendarDayKey`.
      try resetStoreFiles(for: configuration)
      return try ModelContainer(for: schema, configurations: [configuration])
    }
  }

  private static func resetStoreFiles(for configuration: ModelConfiguration) throws {
    let urls = [
      configuration.url,
      URL(fileURLWithPath: configuration.url.path + "-wal"),
      URL(fileURLWithPath: configuration.url.path + "-shm"),
    ]
    let fileManager = FileManager.default
    for url in urls where fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
  }
}
