---
name: new-model
description: Scaffold a new SwiftData @Model class for NetMonitor-2.0. Creates the model file in NetMonitorCore, registers it in SchemaV1, regenerates the Xcode project, and verifies the build.
disable-model-invocation: true
---

## Steps

Ask the user for:
- Model name (e.g. `ConnectionLog`)
- Properties needed (name, type, optional?)
- Which targets use it: macOS only, iOS only, or both

Then:

### 1. Create the model file

Create `Packages/NetMonitorCore/Sources/NetMonitorCore/Models/<ModelName>.swift`:

```swift
import Foundation
import SwiftData

@Model
public final class <ModelName> {
    // properties here

    public init(...) {
        // init here
    }
}
```

Follow these rules:
- `public final class`
- All stored properties `public var`
- `UUID` primary key with `= UUID()` default
- `Date` fields with `= Date()` defaults where appropriate
- Optional fields use `?`

### 2. Register in SchemaV1

Open `NetMonitor-macOS/App/SchemaV1.swift`. Find the `models` array and add `<ModelName>.self`:

```swift
static var models: [any PersistentModel.Type] {
    [
        NetworkTarget.self,
        LocalDevice.self,
        SessionRecord.self,
        ToolActivityLog.self,
        ConnectivityRecord.self,
        <ModelName>.self    // add here
    ]
}
```

### 3. Verify build

```bash
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "error:|Build succeeded|BUILD FAILED"
```

Fix any errors before proceeding.

### 4. Commit

```bash
git add Packages/NetMonitorCore/Sources/NetMonitorCore/Models/<ModelName>.swift \
        NetMonitor-macOS/App/SchemaV1.swift
git commit -m "feat: add <ModelName> SwiftData model"
```
