import Foundation

// Tactile's checks: `swift run tactile-checks`. Pass --no-web to skip the web
// app's tests, which run in a WebKit view.
let checks = Checks()
SecurityChecks.run(checks)
InputChecks.run(checks)
NetworkChecks.run(checks)
if !CommandLine.arguments.contains("--no-web") { WebChecks.run(checks) }
exit(checks.finish())
