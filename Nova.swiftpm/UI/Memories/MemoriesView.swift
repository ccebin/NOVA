import SwiftUI
import SwiftData

public struct MemoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MemoryEntity.updatedAt, order: .reverse) private var memories: [MemoryEntity]
    
    @State private var searchText: String = ""
    @State private var showingAddSheet: Bool = false
    @State private var newKey: String = ""
    @State private var newContent: String = ""
    @State private var newCategory: MemoryCategory = .userPreference
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            List {
                // Summary Card
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(NovaTheme.accentSubtle)
                                .frame(width: 44, height: 44)
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 20))
                                .foregroundColor(NovaTheme.accent)
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Persistent Memory Core")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(NovaTheme.ink)
                            Text("\(memories.count) Structured Local Memories")
                                .font(.system(size: 12))
                                .foregroundColor(NovaTheme.inkSecondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(NovaTheme.surfaceCard)
                }
                
                if memories.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.system(size: 32))
                                .foregroundColor(NovaTheme.inkTertiary)
                            Text("No Persistent Memories Yet")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(NovaTheme.ink)
                            Text("NOVA conservatively stores memories when explicitly requested (e.g. \"Remember that I prefer dark mode\") or when stable preferences are detected.")
                                .font(.system(size: 12))
                                .foregroundColor(NovaTheme.inkSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    // Grouped Memories
                    ForEach(MemoryCategory.allCases, id: \.self) { cat in
                        let catMemories = filteredMemories.filter { $0.category == cat }
                        if !catMemories.isEmpty {
                            Section(header: Text(cat.rawValue).foregroundColor(NovaTheme.inkTertiary)) {
                                ForEach(catMemories) { mem in
                                    memoryRow(mem)
                                }
                                .onDelete { indexSet in
                                    deleteMemories(from: catMemories, at: indexSet)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NovaTheme.canvas)
            .navigationTitle("Memories")
            .searchable(text: $searchText, prompt: "Search local memories")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(NovaTheme.accent)
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                addMemorySheet
            }
            .onAppear {
                MemoryManager.shared.setModelContext(modelContext)
            }
        }
    }
    
    private var filteredMemories: [MemoryEntity] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return memories
        }
        return memories.filter {
            $0.key.localizedCaseInsensitiveContains(trimmed) ||
            $0.content.localizedCaseInsensitiveContains(trimmed) ||
            $0.categoryRaw.localizedCaseInsensitiveContains(trimmed)
        }
    }
    
    private func memoryRow(_ mem: MemoryEntity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(mem.content)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(NovaTheme.ink)
            
            HStack(spacing: 8) {
                // Key chip
                Text(mem.key)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(NovaTheme.inkTertiary)
                
                Spacer()
                
                // Confidence pill
                Text("\(Int(mem.confidence * 100))% conf")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(NovaTheme.statusGreen)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(NovaTheme.statusGreen.opacity(0.12))
                    .clipShape(Capsule())
                
                // Source pill
                Text(mem.source == .explicitUser ? "Explicit" : "Derived")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(NovaTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(NovaTheme.accentSubtle)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(NovaTheme.surfaceCard)
    }
    
    private func deleteMemories(from list: [MemoryEntity], at indexSet: IndexSet) {
        for index in indexSet {
            let item = list[index]
            MemoryManager.shared.deleteMemory(id: item.id)
        }
    }
    
    private var addMemorySheet: some View {
        NavigationStack {
            Form {
                Section("Memory Content") {
                    TextField("e.g. User prefers espresso with no sugar", text: $newContent)
                }
                
                Section("Key / Identifier") {
                    TextField("e.g. pref.coffee", text: $newKey)
                }
                
                Section("Category") {
                    Picker("Category", selection: $newCategory) {
                        ForEach(MemoryCategory.allCases, id: \.self) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                }
            }
            .navigationTitle("New Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showingAddSheet = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if !newContent.isEmpty {
                            let key = newKey.isEmpty ? "memory.\(UUID().uuidString.prefix(6))" : newKey
                            MemoryManager.shared.saveOrUpdateMemory(
                                key: key,
                                content: newContent,
                                category: newCategory,
                                source: .explicitUser,
                                reasonForRetention: "Manually added by user"
                            )
                            newContent = ""
                            newKey = ""
                            showingAddSheet = false
                        }
                    }
                    .disabled(newContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
