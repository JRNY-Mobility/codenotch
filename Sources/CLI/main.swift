import Foundation

// The gate, from a shell. Shares the app's preferences domain so the notch
// and `codenotch project ...` read the same list.
let defaults = UserDefaults(suiteName: ProjectGateCLI.appDefaultsSuite) ?? .standard
let store = ProjectStore(defaults: defaults)
exit(ProjectGateCLI.run(arguments: Array(CommandLine.arguments.dropFirst()), store: store))
