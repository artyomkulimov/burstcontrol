// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "BurstControl", platforms: [.macOS(.v13)], products: [.executable(name: "BurstControl", targets: ["BurstControl"])], targets: [.executableTarget(name: "BurstControl", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("SwiftUI")])])
