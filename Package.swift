// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "RestPause", platforms: [.macOS(.v13)], products: [.executable(name: "RestPause", targets: ["RestPause"])], targets: [.target(name: "RestCore"), .executableTarget(name: "RestPause", dependencies: ["RestCore"], resources: [.copy("Music")]), .executableTarget(name: "RestCoreChecks", dependencies: ["RestCore"])])
