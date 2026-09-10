import SwiftUI
import SwiftData

@main
struct NovaApp: App {
    @StateObject private var appState = AppState()
    
    private let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ConversationEntity.self,
            MessageEntity.self,
            ToolExecutionRecordEntity.self,
            MemoryEntity.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create SwiftData ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(appState)
                .modelContainer(sharedModelContainer)
                .preferredColorScheme(.dark)
                .onAppear {
                    // Initialize memory manager context
                    MemoryManager.shared.setModelContext(sharedModelContainer.mainContext)
                    
                    // Register verified local tools
                    ToolRegistry.shared.register(RemindersTool())
                    ToolRegistry.shared.register(CalendarTool())
                    
                    appState.bootstrap(modelContext: sharedModelContainer.mainContext)
                }
        }
    }
}
