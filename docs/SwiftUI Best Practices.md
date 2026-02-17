# To train an iOS/macOS developer AI (or yourself) on the "bleeding edge" ecosystem for 2025/2026, you must abandon patterns from 2020–2023 (like Combine pipelines for view models and CoreData boilerplate).
The following document outlines the strict standards for modern iOS 18+ and macOS 15+ development.

# iOS & macOS Development Standards (2025/2026 Edition)
Target Environment: iOS 18+, macOS 15+ (Swift 6 mode enabled)
Core Stack: SwiftUI, SwiftData, Swift Concurrency (Strict)

# 1\. Modern State Management: The Observation Framework
*Stop using ObservableObject, @Published, and @StateObject. These are legacy Combine-backed wrappers.*
### The New Standard: @Observable Macro
The Observation framework removes the need for "publishing" changes manually. It relies on access tracking—views only redraw if they *read* a property that changed.
**Best Practices:**
* **Mark models with @Observable**: This transforms the class into a tracking-capable object at compile time.
* **No @Published**: All stored properties are observed by default. Use @ObservationIgnored for properties that shouldn't trigger UI updates (e.g., internal caches or loggers).
* **Binding Generation**: Use the @Bindable property wrapper inside views when you need to create bindings (like $model.name) from an observable object.

⠀**Legacy vs. Modern Comparison:**
| **Feature** | **Legacy (Combine)** | **Modern (Observation)** |
|---|---|---|
| **Declaration** | class Store: ObservableObject | @Observable class Store |
| **Properties** | @Published var count = 0 | var count = 0 |
| **Injection** | @StateObject / @ObservedObject | @State / plain property |
| **Performance** | Redraws view on *any* published change | Redraws *only* if the specific property is read |
**Code Standard:**
Swift

@Observable
final class UserProfile {
    var name: String = "Guest"
    var isPremium: Bool = false
    
    // UI will NOT update when this changes
    @ObservationIgnored var lastSyncTimestamp: Date = .now
}

struct ProfileView: View {
    @State var profile = UserProfile() // @State now manages lifecycle of reference types too

    var body: some View {
        // Only updates when 'name' changes.
        // Changing 'isPremium' will NOT trigger a redraw of this specific view.
        Text(profile.name)
        
        // Use @Bindable to create bindings for controls
        EditProfileView(profile: profile)
    }
}

struct EditProfileView: View {
    @Bindable var profile: UserProfile // Creates $profile.name bindings
    
    var body: some View {
        TextField("Name", text: $profile.name)
    }
}

# 2\. Persistence: SwiftData & Synchronous Updates
*Core Data is deprecated for new feature work. SwiftData is the primary persistence engine.*
### Synchronous UI Updates
SwiftData on the @MainActor is designed to be synchronous for the UI. When you modify a model in the modelContext(main actor), @Query updates the UI immediately in the same run-loop tick. You do not need await for fetching data to drive the UI.
**Best Practices:**
* **Use @Query for Read-Only Views**: Let SwiftUI handle the fetching. It automatically monitors the context for changes (inserts, deletes, updates).
* **Implicit Saves**: Do not call context.save() manually unless strictly necessary (e.g., before sharing data to an extension). SwiftData autosaves on UI life-cycle events (backgrounding, etc.).
* **Strict Concurrency for Writes**: Never pass a ModelContext or a generic @Model object between threads/actors. If you need to do background work, pass the PersistentIdentifier and create a new context on that background actor.

⠀Handling Preview Data:
Use a custom ModelContainer configuration stored in memory for previews to prevent polluting the production database.
**Code Standard:**
Swift

import SwiftData

@Model
final class TodoItem {
    var title: String
    var isDone: Bool
    var createdAt: Date
    
    init(title: String, isDone: Bool = false) {
        self.title = title
        self.isDone = isDone
        self.createdAt = .now
    }
}

struct TodoListView: View {
    // Automatically fetches, observes, and animates changes
    @Query(sort: \.createdAt, order: .reverse) private var items: [TodoItem]
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            ForEach(items) { item in
                Toggle(item.title, isOn: Bindable(item).isDone) // Direct binding to DB model
            }
            .onDelete(perform: deleteItems)
        }
    }

    // This is synchronous and immediately reflects in the UI
    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            context.delete(items[index])
        }
        // No save() needed; UI updates instantly
    }
}

# 3\. Strict Concurrency (Swift 6)
*The compiler now treats data races as build errors, not warnings. The "Main Actor" is your default home.*
### The Golden Rules of Swift 6
1. **Views are @MainActor**: All SwiftUI Views are implicitly main-actor isolated.
2. **ViewModels (if used) must be @MainActor**: Annotate your observation classes with @MainActor to ensure all property updates happen on the main thread.
3. **Sendable is Mandatory**: Any data passed between async tasks must conform to Sendable. Structs and Enums are Sendable by default; Classes are not (unless final and immutable).

⠀Handling Async Actions:
Do not use DispatchQueue.main.async. Use Swift Concurrency tasks.
Swift

@MainActor // 1. Lock class to main thread
@Observable
class DataModel {
    var items: [String] = []

    func loadData() async {
        // 2. Perform heavy work off-thread automatically
        let fetchedItems = await fetchFromNetwork() 
        
        // 3. Back on MainActor automatically after await
        self.items = fetchedItems
    }
    
    // nonisolated allows this function to run on ANY thread (good for pure logic)
    nonisolated func filterLogic(_ input: [String]) -> [String] {
        return input.filter { $0.count > 5 }
    }
}

# 4\. Modern Architecture: "View is the ViewModel"
With @Observable and SwiftData, the heavy MVVM (Model-View-ViewModel) pattern is often redundant.
**The "Pragmatic" Architecture:**
* **Simple Screens:** Let the View own the state and @Query the data directly.
* **Complex Logic:** Extract logic into a @MainActor isolated @Observable class (a lightweight StateHolder), but strictly for *state*, not for pass-through boilerplate.
* **Data Access:** Do not wrap SwiftData logic in a "Repository" class unless you are sharing code with a non-SwiftUI target. @Query is highly optimized for performance; wrapping it breaks its optimizations.

⠀
# 5\. UI Best Practices for Newer Devices
Targeting iPhone 16/17 Pro and M4/M5 Macs requires utilizing the full screen and fluid interactions.
* **Look & Feel:**
  * Use .containerRelativeFrame for adaptive layouts instead of GeometryReader.
  * Use .scrollTargetBehavior(.viewAligned) for modern, snapping carousel UIs.
  * Use Material backgrounds (.regularMaterial, .ultraThinMaterial) to adapt to system wallpapers/modes.
* **Navigation:**
  * Use NavigationStack with navigationDestination(for: Type.self).
  * Avoid NavigationLink inside lists for performance; use value-based navigation.

⠀**Code Standard (Navigation):**
Swift

@Observable
class Router {
    var path = NavigationPath()
}

struct AppRoot: View {
    @State var router = Router()

    var body: some View {
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Item.self) { item in
                    DetailView(item: item)
                }
        }
        .environment(router)
    }
}

# Summary Checklist for the AI
When generating code, the AI must check:
1. [ ] Is ObservableObject used? **REJECT**. Use @Observable.
2. [ ] Is @Published used? **REJECT**. Properties are observable by default.
3. [ ] Is CoreData used? **REJECT**. Use SwiftData.
4. [ ] Is @StateObject used? **REJECT**. Use @State for lifecycle ownership.
5. [ ] Is the data passed across actors Sendable? **REQUIRED**.
6. [ ] Are SwiftData updates performed on the MainContext for synchronous UI reflection? **YES**.
