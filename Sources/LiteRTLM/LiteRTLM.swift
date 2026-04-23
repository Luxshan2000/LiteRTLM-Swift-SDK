// LiteRTLM Swift SDK
//
// Production-grade Swift wrapper for Google's LiteRT-LM on-device inference engine.
// Supports iOS 17+ and iPadOS 17+.
//
// Quick start:
//
//   import LiteRTLM
//   import LiteRTLMDownloader
//
//   // 1. Download model
//   let downloader = ModelDownloader()
//   await downloader.download(model: .gemma4E2B)
//
//   // 2. Create engine
//   let config = EngineConfiguration(modelPath: downloader.modelPath(for: .gemma4E2B)!)
//       .backend(.gpu)
//   let engine = LMEngine(configuration: config)
//   try await engine.load()
//
//   // 3a. One-shot generation
//   let session = try await engine.createSession()
//   for try await token in session.generateStream("Explain quantum computing") {
//       print(token, terminator: "")
//   }
//
//   // 3b. Multi-turn conversation
//   let conversation = try await engine.createConversation()
//   let reply = try await conversation.send("Hello!")
//   let followUp = try await conversation.send("Tell me more")
//
//   // 3c. Vision
//   let conversation = try await engine.createConversation()
//   let description = try await conversation.send(
//       "Describe this image",
//       images: [photoData]
//   )
//
//   // 4. Cleanup
//   session.close()
//   conversation.close()
//   engine.unload()

// All public types (LMEngine, LMSession, LMConversation, TokenStream, Tool,
// Content, Message, BenchmarkInfo, configurations, errors, etc.) are available
// via a single `import LiteRTLM`.
