import CryptoKit
import Foundation
import Security

/// Keeps Tactile up to date from its GitHub releases: checks for a newer one,
/// and on request downloads it, checks it, and puts it in place of the app
/// that's running. The app then reopens itself (see `onInstalled`).
///
/// A download is installed only if it matches its published SHA-256 checksum
/// and is signed with the same certificate as the running app, which only
/// the release workflow has. Anything else leaves the running app untouched.
public final class Updater {
    public struct Release: Equatable {
        public var version: String
        /// The release notes, on GitHub.
        public var notes: URL
        var zip: URL
        var checksum: URL
        var size: Int
    }

    public enum State: Equatable {
        case idle
        case checking
        case upToDate(version: String)
        case available(Release)
        case downloading(Release, progress: Double)
        case installing(Release)
        /// `canRetry` is false when trying again wouldn't help (Tactile can't
        /// replace itself where it is); the release page is the way out then.
        case failed(Release, reason: String, canRetry: Bool)

        /// The release this state is about, if any.
        public var release: Release? {
            switch self {
            case .available(let release), .downloading(let release, _), .installing(let release), .failed(let release, _, _):
                release
            case .idle, .checking, .upToDate:
                nil
            }
        }
    }

    public static let repository = "KukretiShubham/tactile-keyboard"
    /// Releases are about 10 MB; anything far bigger isn't one.
    static let largestDownload = 200 << 20

    /// Called on the main queue whenever the state changes.
    public var onChange: ((State) -> Void)?
    /// Called on the main queue once the new version is in place, with where
    /// it is, so the app can reopen into it.
    public var onInstalled: ((URL) -> Void)?

    public private(set) var state: State = .idle {
        didSet {
            let state = state
            DispatchQueue.main.async { self.onChange?(state) }
        }
    }

    private let currentVersion: String
    private let appURL: URL
    private let latest: URL
    private let requirement: SecRequirement?
    private let queue = DispatchQueue(label: "tactile.updates")
    private var download: Download?

    /// - Parameters:
    ///   - appURL: The installed app, which an update replaces.
    ///   - requirement: What a new version's signature must satisfy; by
    ///     default, the running app's own (so: the same certificate).
    ///   - latest: Where the latest release is described (GitHub's API).
    public init(currentVersion: String, appURL: URL, requirement: SecRequirement? = Updater.ownRequirement(),
                latest: URL = URL(string: "https://api.github.com/repos/\(Updater.repository)/releases/latest")!) {
        self.currentVersion = currentVersion
        self.appURL = appURL
        self.requirement = requirement
        self.latest = latest
    }

    /// The running app's designated requirement: its identifier and signing
    /// certificate. Nil when it can't be read.
    public static func ownRequirement() -> SecRequirement? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }

    // MARK: Checking

    /// Looks for a newer release. `quietly` (the automatic daily check) skips
    /// the "Checking…" and "Up to Date" states and keeps quiet about errors.
    public func check(quietly: Bool = false) {
        queue.async {
            switch self.state {
            case .downloading, .installing, .checking: return
            default: break
            }
            if !quietly { self.state = .checking }
            var request = URLRequest(url: self.latest, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            URLSession.shared.dataTask(with: request) { data, response, _ in
                let ok = ((response as? HTTPURLResponse)?.statusCode ?? 200) == 200
                self.queue.async { self.checked(data, ok: ok, quietly: quietly) }
            }.resume()
        }
    }

    private func checked(_ data: Data?, ok: Bool, quietly: Bool) {
        guard ok, let data, let release = Self.release(from: data) else {
            if !quietly { Log.warn("Couldn't check for updates.") }
            // An update already found stays on offer.
            if state.release == nil { state = .idle }
            return
        }
        if Self.isNewer(release.version, than: currentVersion) {
            state = .available(release)
        } else if quietly {
            state = .idle
        } else {
            // "Up to Date" shows for a moment, then the row goes back to normal.
            state = .upToDate(version: currentVersion)
            queue.asyncAfter(deadline: .now() + 4) {
                if case .upToDate = self.state { self.state = .idle }
            }
        }
    }

    /// The release GitHub describes, if it has a Tactile download and its
    /// checksum (`Tactile-v1.2.0.zip` and `.zip.sha256`).
    static func release(from json: Data) -> Release? {
        guard let release = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let tag = release["tag_name"] as? String, tag.hasPrefix("v"),
              let notes = (release["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = release["assets"] as? [[String: Any]] else { return nil }
        func asset(_ name: String) -> (url: URL, size: Int)? {
            guard let asset = assets.first(where: { $0["name"] as? String == name }),
                  let url = (asset["browser_download_url"] as? String).flatMap(URL.init(string:)) else { return nil }
            return (url, (asset["size"] as? Int) ?? 0)
        }
        guard let zip = asset("Tactile-\(tag).zip"), let checksum = asset("Tactile-\(tag).zip.sha256") else { return nil }
        return Release(version: String(tag.dropFirst()), notes: notes, zip: zip.url, checksum: checksum.url, size: zip.size)
    }

    /// Compares dotted version numbers: 1.10.0 is newer than 1.9.2.
    public static func isNewer(_ version: String, than current: String) -> Bool {
        let parts = { (text: String) in text.split(separator: ".").map { Int($0) ?? 0 } }
        let (a, b) = (parts(version), parts(current))
        for index in 0..<max(a.count, b.count) {
            let (x, y) = (index < a.count ? a[index] : 0, index < b.count ? b[index] : 0)
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Installing

    /// Downloads, checks and installs the release on offer (or retries one
    /// that failed).
    public func install() {
        queue.async {
            let release: Release
            switch self.state {
            case .available(let offered), .failed(let offered, _, true): release = offered
            default: return
            }
            guard FileManager.default.isWritableFile(atPath: self.appURL.deletingLastPathComponent().path) else {
                self.state = .failed(release, reason: "Tactile can’t replace itself in this folder.", canRetry: false)
                return
            }
            guard release.size <= Self.largestDownload else {
                self.state = .failed(release, reason: "The download is too big to be Tactile.", canRetry: false)
                return
            }
            self.state = .downloading(release, progress: 0)
            self.fetchChecksum(of: release)
        }
    }

    /// The checksum comes first: it's tiny, and without it the download
    /// couldn't be checked anyway.
    private func fetchChecksum(of release: Release) {
        let request = URLRequest(url: release.checksum, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let ok = ((response as? HTTPURLResponse)?.statusCode ?? 200) == 200
            self.queue.async {
                guard case .downloading = self.state else { return } // cancelled
                guard ok, let data, let checksum = String(data: data, encoding: .utf8) else {
                    return self.fail(release, "Couldn’t get the download’s checksum.")
                }
                self.download = Download(url: release.zip, queue: self.queue, progress: { [weak self] fraction in
                    // A redraw per whole percent, not per network packet.
                    guard case .downloading(_, let shown) = self?.state, Int(fraction * 100) > Int(shown * 100) else { return }
                    self?.state = .downloading(release, progress: fraction)
                }) { [weak self] file in
                    self?.downloaded(file, release, checksum: checksum)
                }
            }
        }.resume()
    }

    /// Stops a download in progress; the release stays on offer.
    public func cancel() {
        queue.async {
            guard case .downloading(let release, _) = self.state else { return }
            self.download?.cancel()
            self.download = nil
            self.state = .available(release)
        }
    }

    private func downloaded(_ file: URL?, _ release: Release, checksum: String) {
        guard case .downloading = state else { return } // cancelled
        download = nil
        guard let file else { return fail(release, "The download didn’t finish.") }
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        state = .installing(release)
        do {
            let staged = try Self.stage(file, checksum: checksum, version: release.version, requirement: requirement)
            defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }
            try Self.replace(appURL, with: staged)
            Log.info("Updated Tactile to \(release.version).")
            let appURL = appURL
            DispatchQueue.main.async { self.onInstalled?(appURL) }
        } catch {
            fail(release, "\(error)")
        }
    }

    private func fail(_ release: Release, _ reason: String) {
        Log.warn("Couldn't update to \(release.version): \(reason)")
        state = .failed(release, reason: reason, canRetry: true)
    }

    enum Failure: Error, CustomStringConvertible {
        case checksum, unpack, notTactile, signature(OSStatus)

        var description: String {
            switch self {
            case .checksum: "The download doesn’t match its checksum."
            case .unpack: "The download couldn’t be opened."
            case .notTactile: "The download isn’t this version of Tactile."
            case .signature: "The download isn’t signed by Tactile’s release certificate."
            }
        }
    }

    /// Checks a downloaded zip and unpacks it into a private folder. Returns
    /// the app inside, ready to move into place; throws if anything is off.
    static func stage(_ zip: URL, checksum: String, version: String, requirement: SecRequirement?) throws -> URL {
        guard let expected = checksum.split(whereSeparator: \.isWhitespace).first.map(String.init)?.lowercased(),
              let data = try? Data(contentsOf: zip, options: .mappedIfSafe),
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expected else { throw Failure.checksum }

        let folder = try Paths.temporaryDirectory()
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, folder.path]
        try unzip.run()
        unzip.waitUntilExit()
        let app = folder.appendingPathComponent("Tactile.app")
        guard unzip.terminationStatus == 0, FileManager.default.fileExists(atPath: app.path) else {
            try? FileManager.default.removeItem(at: folder)
            throw Failure.unpack
        }
        do {
            let info = Bundle(url: app)?.infoDictionary
            guard info?["CFBundleIdentifier"] as? String == "app.tactile.mac",
                  info?["CFBundleShortVersionString"] as? String == version else { throw Failure.notTactile }
            try verifySignature(of: app, requirement: requirement)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return app
    }

    /// Puts `new` where `app` is. The new app first moves next to the old one
    /// (the private folder may be on another volume), then the two swap and
    /// the old one is deleted, so no old versions pile up.
    static func replace(_ app: URL, with new: URL) throws {
        let beside = app.deletingLastPathComponent().appendingPathComponent(".Tactile-update-\(UUID().uuidString).app")
        try FileManager.default.moveItem(at: new, to: beside)
        do {
            _ = try FileManager.default.replaceItemAt(app, withItemAt: beside)
        } catch {
            try? FileManager.default.removeItem(at: beside)
            throw error
        }
    }

    /// Checks the app's signature is intact (every file, every architecture)
    /// and satisfies `requirement`. A missing requirement fails: an app that
    /// can't say what it's signed by can't vouch for an update.
    static func verifySignature(of app: URL, requirement: SecRequirement?) throws {
        guard let requirement else { throw Failure.signature(errSecCSReqFailed) }
        var code: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(app as CFURL, [], &code)
        if status == errSecSuccess, let code {
            let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
            status = SecStaticCodeCheckValidity(code, flags, requirement)
        }
        guard status == errSecSuccess else { throw Failure.signature(status) }
    }
}

/// One download with progress, to a file of its own. Everything, from
/// progress to finishing or cancelling, happens on the caller's queue.
private final class Download: NSObject, URLSessionDownloadDelegate {
    private var session: URLSession!
    private let progress: (Double) -> Void
    private let done: (URL?) -> Void
    private var finished = false

    init(url: URL, queue: DispatchQueue, progress: @escaping (Double) -> Void, done: @escaping (URL?) -> Void) {
        self.progress = progress
        self.done = done
        super.init()
        let delegateQueue = OperationQueue()
        delegateQueue.underlyingQueue = queue
        session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: delegateQueue)
        session.downloadTask(with: url).resume()
    }

    func cancel() {
        finished = true
        session.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten written: Int64, totalBytesExpectedToWrite expected: Int64) {
        if expected > 0 { progress(Double(written) / Double(expected)) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The file is deleted when this returns, so keep it somewhere private.
        guard !finished, (downloadTask.response as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? true,
              let folder = try? Paths.temporaryDirectory() else { return }
        let kept = folder.appendingPathComponent("Tactile.zip")
        finished = (try? FileManager.default.moveItem(at: location, to: kept)) != nil
        done(finished ? kept : nil)
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if !finished {
            finished = true
            done(nil)
        }
    }
}
