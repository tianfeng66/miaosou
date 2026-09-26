import AppKit

if CommandLine.arguments.contains("--search") || CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    SpotlightCLI.run(arguments: CommandLine.arguments)
}

autoreleasepool {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
