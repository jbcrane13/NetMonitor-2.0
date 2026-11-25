import AppKit
import ApplicationServices

// Drives the running NetMonitor-macOS app through the Accessibility API, by accessibility
// identifier, and captures only its window. Build: swiftc -O scripts/ax/axdrive.swift -o <out>. Usage:
//   axdrive press <id> | click <id> | type <id> <text> | wait <id> <seconds> | gone <id> <seconds>
//   axdrive capture <file.png> | ids | value <id> | menu <menu item title>
//   axdrive text <substring> <seconds> | notext <substring> <seconds>  (any element's value, title or description)
//   axdrive textin <id> <substring> <seconds> | notextin <id> <substring> <seconds>  (only in elements
//                                            carrying <id> and their descendants, such as one card)
//   axdrive capture-element <id> <file.png>  (only that element's frame on screen)
//   axdrive pressin <id> <title>  (presses the descendant of <id> titled <title>, such as a picker segment)
//   axdrive capture-in <id> <file.png>  (the app window only, cropped to that element; no other window shows)
//   axdrive capture-union <file.png> <id>...  (the app window only, cropped to every element carrying any of
//                                            the ids, for content macOS 27 stamps one identifier across)
//   axdrive typefield <id> <text>  (types into the first text field with or inside <id>, for a container
//                                  whose identifier macOS 27 stamps over its children's)
let args = CommandLine.arguments
guard args.count >= 2 else { print("usage")
exit(2)
}

// AX_PID picks one process, so the driver never touches another copy of the app (such as the
// installed one) that shares the bundle identifier.
func app() -> NSRunningApplication? {
    if let pid = ProcessInfo.processInfo.environment["AX_PID"].flatMap(pid_t.init) {
        return NSRunningApplication(processIdentifier: pid)
    }
    return NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.netmonitor.NetMonitor" }
}

func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success ? value : nil
}

func find(_ id: String) -> AXUIElement? {
    guard let pid = app()?.processIdentifier else { return nil }
    let root = AXUIElementCreateApplication(pid)
    var queue: [AXUIElement] = [root]
    var seen = 0
    while !queue.isEmpty, seen < 20000 {
        let el = queue.removeFirst()
        seen += 1
        if let ident = attr(el, "AXIdentifier") as? String, ident == id {
            return el
        }
        if let children = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
            queue += children
        }
    }
    return nil
}

/// Every element whose identifier is in `ids`.
func findAll(_ ids: Set<String>) -> [AXUIElement] {
    guard let pid = app()?.processIdentifier else { return [] }
    var queue: [AXUIElement] = [AXUIElementCreateApplication(pid)]
    var found: [AXUIElement] = []
    var seen = 0
    while !queue.isEmpty, seen < 20000 {
        let el = queue.removeFirst()
        seen += 1
        if let ident = attr(el, "AXIdentifier") as? String, ids.contains(ident) {
            found.append(el)
        }
        if let children = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
            queue += children
        }
    }
    return found
}

/// An element's frame on screen, when it has one.
func frame(of el: AXUIElement) -> CGRect? {
    guard let posValue = attr(el, kAXPositionAttribute), let sizeValue = attr(el, kAXSizeAttribute),
          CFGetTypeID(posValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
    else { return nil }
    var pos = CGPoint.zero, size = CGSize.zero
    // swiftlint:disable force_cast
    AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    // swiftlint:enable force_cast
    return CGRect(origin: pos, size: size)
}

func menuItem(titled title: String) -> AXUIElement? {
    guard let pid = app()?.processIdentifier else { return nil }
    var queue: [AXUIElement] = [AXUIElementCreateApplication(pid)]
    while !queue.isEmpty {
        let el = queue.removeFirst()
        if attr(el, kAXRoleAttribute) as? String == kAXMenuItemRole, attr(el, kAXTitleAttribute) as? String == title {
            return el
        }
        if let children = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
            queue += children
        }
    }
    return nil
}

func allIDs() -> [String] {
    guard let pid = app()?.processIdentifier else { return [] }
    var queue: [AXUIElement] = [AXUIElementCreateApplication(pid)]
    var ids: [String] = []
    while !queue.isEmpty {
        let el = queue.removeFirst()
        if let ident = attr(el, "AXIdentifier") as? String, !ident.isEmpty {
            ids.append(ident)
        }
        if let children = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
            queue += children
        }
    }
    return ids
}

/// Whether any element's value, title or description contains `text`. For content whose container
/// identifier is stamped over its children's on macOS 27.
func hasText(_ text: String) -> Bool {
    guard let pid = app()?.processIdentifier else { return false }
    var queue: [AXUIElement] = [AXUIElementCreateApplication(pid)]
    var seen = 0
    while !queue.isEmpty, seen < 20000 {
        let el = queue.removeFirst()
        seen += 1
        for name in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            if let string = attr(el, name) as? String, string.contains(text) {
                return true
            }
        }
        if let children = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
            queue += children
        }
    }
    return false
}

/// Whether an element carrying `id`, or one inside it, shows `text` in its title, value or description.
func hasText(_ text: String, inside id: String) -> Bool {
    var queue = findAll([id])
    while !queue.isEmpty {
        let el = queue.removeFirst()
        for name in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] where (attr(el, name) as? String)?.contains(text) == true {
            return true
        }
        queue += attr(el, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    return false
}

func waitForText(_ text: String, _ seconds: Double, present: Bool, inside id: String? = nil) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if (id.map { hasText(text, inside: $0) } ?? hasText(text)) == present {
            return true
        }
        usleep(300_000)
    }
    return false
}

/// The first descendant of `root` whose title, value or description is exactly `title`.
func descendant(of root: AXUIElement, titled title: String) -> AXUIElement? {
    var queue = attr(root, kAXChildrenAttribute) as? [AXUIElement] ?? []
    while !queue.isEmpty {
        let el = queue.removeFirst()
        for name in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] where attr(el, name) as? String == title {
            return el
        }
        queue += attr(el, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    return nil
}

/// The first text field with identifier `id`, or inside an element with it: macOS 27 stamps a
/// container's identifier over its children's, so the field may carry the container's.
func textField(_ id: String) -> AXUIElement? {
    guard let pid = app()?.processIdentifier else { return nil }
    var queue: [(AXUIElement, Bool)] = [(AXUIElementCreateApplication(pid), false)]
    var seen = 0
    while !queue.isEmpty, seen < 20000 {
        let (el, insideID) = queue.removeFirst()
        seen += 1
        let inside = insideID || attr(el, "AXIdentifier") as? String == id
        if inside, attr(el, kAXRoleAttribute) as? String == kAXTextFieldRole {
            return el
        }
        queue += (attr(el, kAXChildrenAttribute) as? [AXUIElement] ?? []).map { ($0, inside) }
    }
    return nil
}

func center(_ el: AXUIElement) -> CGPoint? {
    guard let posValue = attr(el, kAXPositionAttribute), let sizeValue = attr(el, kAXSizeAttribute),
          CFGetTypeID(posValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
    else { return nil }
    var pos = CGPoint.zero, size = CGSize.zero
    // swiftlint:disable force_cast
    AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    // swiftlint:enable force_cast
    return CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
}

func mouseClick(_ point: CGPoint) {
    let src = CGEventSource(stateID: .hidSystemState)
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(60_000)
    }
}

func waitFor(_ id: String, _ seconds: Double, present: Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if (find(id) != nil) == present {
            return true
        }
        usleep(300_000)
    }
    return false
}

func windowID() -> CGWindowID? {
    guard let pid = app()?.processIdentifier,
          let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return nil }
    let windows = list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
    let biggest = windows.max { lhs, rhs in
        let ra = lhs[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
        let rb = rhs[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
        return (ra["Width"] ?? 0) * (ra["Height"] ?? 0) < (rb["Width"] ?? 0) * (rb["Height"] ?? 0)
    }
    return (biggest?[kCGWindowNumber as String] as? Int).map { CGWindowID($0) }
}

app()?.activate()
usleep(200_000)
switch args[1] {
case "press":
    guard let el = find(args[2]) else { print("NOTFOUND \(args[2])")
    exit(1)
    }
    if AXUIElementPerformAction(el, kAXPressAction as CFString) != .success, let point = center(el) {
        mouseClick(point)
    }
    print("pressed \(args[2])")
case "click":
    guard let el = find(args[2]), let point = center(el) else { print("NOTFOUND \(args[2])")
    exit(1)
    }
    mouseClick(point)
    print("clicked \(args[2]) at \(point)")
case "type", "typefield":
    guard let found = find(args[2]) else { print("NOTFOUND \(args[2])")
    exit(1)
    }
    var el = found
    if args[1] == "typefield" {
        guard let field = textField(args[2]) else { print("NOFIELD \(args[2])")
        exit(1)
        }
        el = field
    }
    AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    if let point = center(el) {
        mouseClick(point)
    }
    usleep(200_000)
    AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, args[3] as CFString)
    // SwiftUI bindings update on typing; nudge with a space + delete so the binding sees a change.
    let src = CGEventSource(stateID: .hidSystemState)
    for (key, _) in [(49, 0), (51, 0)] {
        CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(key), keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(key), keyDown: false)?.post(tap: .cghidEventTap)
        usleep(80_000)
    }
    print("typed \(args[2])")
case "wait":
    print(waitFor(args[2], Double(args[3]) ?? 10, present: true) ? "found \(args[2])" : "TIMEOUT \(args[2])")
case "gone":
    print(waitFor(args[2], Double(args[3]) ?? 10, present: false) ? "gone \(args[2])" : "STILL \(args[2])")
case "value":
    if let el = find(args[2]) {
        print(attr(el, kAXValueAttribute) ?? attr(el, kAXTitleAttribute) ?? attr(el, kAXDescriptionAttribute) ?? "nil")
    } else {
        print("NOTFOUND")
    }
case "menu":
    guard let el = menuItem(titled: args[2]), AXUIElementPerformAction(el, kAXPressAction as CFString) == .success else {
        print("NOTFOUND \(args[2])")
        exit(1)
    }
    print("pressed menu \(args[2])")
case "text":
    print(waitForText(args[2], Double(args[3]) ?? 10, present: true) ? "found text \(args[2])" : "TIMEOUT text \(args[2])")
case "notext":
    print(waitForText(args[2], Double(args[3]) ?? 10, present: false) ? "no text \(args[2])" : "STILL text \(args[2])")
case "textin":
    print(waitForText(args[3], Double(args[4]) ?? 10, present: true, inside: args[2]) ? "found text \(args[3])" : "TIMEOUT text \(args[3])")
case "notextin":
    print(waitForText(args[3], Double(args[4]) ?? 10, present: false, inside: args[2]) ? "no text \(args[3])" : "STILL text \(args[3])")
case "capture-element":
    guard let el = find(args[2]), let posValue = attr(el, kAXPositionAttribute), let sizeValue = attr(el, kAXSizeAttribute),
          CFGetTypeID(posValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
    else { print("NOTFOUND \(args[2])")
        exit(1)
    }
    var pos = CGPoint.zero, size = CGSize.zero
    // swiftlint:disable force_cast
    AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    // swiftlint:enable force_cast
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-R\(Int(pos.x)),\(Int(pos.y)),\(Int(size.width)),\(Int(size.height))", args[3]]
    try task.run()
    task.waitUntilExit()
    print("captured \(args[2]) to \(args[3])")
case "pressin":
    guard let root = find(args[2]), let el = descendant(of: root, titled: args[3]) else {
        print("NOTFOUND \(args[3]) in \(args[2])")
        exit(1)
    }
    if AXUIElementPerformAction(el, kAXPressAction as CFString) != .success, let point = center(el) {
        mouseClick(point)
    }
    print("pressed \(args[3]) in \(args[2])")
case "capture-in":
    guard let el = find(args[2]), let posValue = attr(el, kAXPositionAttribute), let sizeValue = attr(el, kAXSizeAttribute),
          CFGetTypeID(posValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID(), let wid = windowID(),
          let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], wid) as? [[String: Any]])?.first,
          let bounds = info[kCGWindowBounds as String] as? [String: CGFloat]
    else { print("NOTFOUND \(args[2])")
        exit(1)
    }
    var pos = CGPoint.zero, size = CGSize.zero
    // swiftlint:disable force_cast
    AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    // swiftlint:enable force_cast
    let full = args[3] + ".window.png"
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-o", "-l\(wid)", full]
    try task.run()
    task.waitUntilExit()
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: full) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { print("NOIMAGE")
        exit(1)
    }
    let scale = CGFloat(image.width) / (bounds["Width"] ?? 1)
    let rect = CGRect(x: (pos.x - (bounds["X"] ?? 0)) * scale, y: (pos.y - (bounds["Y"] ?? 0)) * scale,
                      width: size.width * scale, height: size.height * scale)
    guard let cropped = image.cropping(to: rect),
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[3]) as CFURL, "public.png" as CFString, 1, nil)
    else { print("NOCROP")
        exit(1)
    }
    CGImageDestinationAddImage(dest, cropped, nil)
    try? FileManager.default.removeItem(atPath: full)
    guard CGImageDestinationFinalize(dest) else { print("NOWRITE \(args[3])")
        exit(1)
    }
    print("captured \(args[2]) to \(args[3])")
case "capture-union":
    let frames = findAll(Set(args.dropFirst(3))).compactMap(frame(of:)).filter { $0.width > 0 && $0.height > 0 }
    guard let union = frames.first.map({ frames.dropFirst().reduce($0) { $0.union($1) } }), let wid = windowID(),
          let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], wid) as? [[String: Any]])?.first,
          let bounds = info[kCGWindowBounds as String] as? [String: CGFloat]
    else { print("NOTFOUND \(args.dropFirst(3).joined(separator: " "))")
        exit(1)
    }
    let full = args[2] + ".window.png"
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-o", "-l\(wid)", full]
    try task.run()
    task.waitUntilExit()
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: full) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { print("NOIMAGE")
        exit(1)
    }
    let scale = CGFloat(image.width) / (bounds["Width"] ?? 1)
    let rect = CGRect(x: (union.minX - (bounds["X"] ?? 0)) * scale, y: (union.minY - (bounds["Y"] ?? 0)) * scale,
                      width: union.width * scale, height: union.height * scale)
    guard let cropped = image.cropping(to: rect),
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, "public.png" as CFString, 1, nil)
    else { print("NOCROP")
        exit(1)
    }
    CGImageDestinationAddImage(dest, cropped, nil)
    try? FileManager.default.removeItem(atPath: full)
    guard CGImageDestinationFinalize(dest) else { print("NOWRITE \(args[2])")
        exit(1)
    }
    print("captured \(frames.count) elements to \(args[2])")
case "ids":
    print(allIDs().joined(separator: "\n"))
case "capture":
    guard let wid = windowID() else { print("NOWINDOW")
    exit(1)
    }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-o", "-l\(wid)", args[2]]
    try task.run()
    task.waitUntilExit()
    print("captured \(args[2])")
default:
    print("unknown")
}
