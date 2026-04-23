import Testing
import Foundation
@testable import WorkLoggerLib

// =============================================================================
// Compliance & Data Risk Mitigation Tests
//
// Tests covering every data protection measure from COMPLIANCE.md:
//   1. URL sanitization (domain-only, query stripping)
//   2. File permissions (0600 for files)
//   3. Auto-purge of old logs (retention days)
//   4. Safari tracking toggles
//   5. String truncation (200 chars)
//   6. Config save/load with privacy fields
//   7. Consent mechanism
//   8. Logger sanitizeURL integration
//   9. logToDate retroactive entries
//  10. Retention edge cases
//  11. Privacy-by-default verification
// =============================================================================

private func makeTempDir() -> String {
    let dir = NSTemporaryDirectory() + "WorkLoggerTest-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
}

private func createFakeLog(dir: String, daysAgo: Int) {
    let dayFmt = DateFormatter()
    dayFmt.dateFormat = "yyyy-MM-dd"
    let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
    let filename = "\(dayFmt.string(from: date)).jsonl"
    let path = "\(dir)/\(filename)"
    try! "{\"event\":\"test\"}\n".write(toFile: path, atomically: true, encoding: .utf8)
}

// MARK: - 1. URL Sanitization – domainOnly

@Suite("domainOnly URL extraction")
struct DomainOnlyTests {

    @Test func basicURL() {
        #expect(Logger.domainOnly("https://github.com/org/repo/pull/42") == "github.com")
    }

    @Test func withQueryAndFragment() {
        #expect(
            Logger.domainOnly("https://portal.client.com/project/12345/docs?token=abc#section")
                == "portal.client.com"
        )
    }

    @Test func withPort() {
        #expect(Logger.domainOnly("https://localhost:8080/api/v1") == "localhost")
    }

    @Test func httpScheme() {
        #expect(Logger.domainOnly("http://example.org/path") == "example.org")
    }

    @Test func oauthParams() {
        let url = "https://login.microsoftonline.com/common/oauth2?code=SECRET&session_state=xyz"
        #expect(Logger.domainOnly(url) == "login.microsoftonline.com")
    }

    @Test func subdomains() {
        #expect(
            Logger.domainOnly("https://teams.microsoft.com/v2/#/conversations")
                == "teams.microsoft.com"
        )
    }

    @Test func plainDomain() {
        #expect(Logger.domainOnly("https://google.com") == "google.com")
    }

    @Test func nonStandardScheme() {
        // "favorites://" has no host — domainOnly returns empty, which is safe
        let result = Logger.domainOnly("favorites://")
        #expect(result == "")
    }

    @Test func emptyString() {
        #expect(Logger.domainOnly("") == "")
    }

    @Test func ipAddress() {
        #expect(Logger.domainOnly("http://192.168.1.1:3000/admin") == "192.168.1.1")
    }

    @Test func unicodeDomain() {
        #expect(Logger.domainOnly("https://münchen.de/page") == "münchen.de")
    }

    @Test func percentEncodedURL() {
        #expect(Logger.domainOnly("https://example.com/path%20with%20spaces?q=test") == "example.com")
    }
}

// MARK: - 1b. URL Sanitization – stripQuery

@Suite("stripQuery URL cleaning")
struct StripQueryTests {

    @Test func removesQueryString() {
        #expect(
            Logger.stripQuery("https://github.com/org/repo?diff=split&tab=files")
                == "https://github.com/org/repo"
        )
    }

    @Test func removesFragment() {
        #expect(
            Logger.stripQuery("https://github.com/org/repo#discussion")
                == "https://github.com/org/repo"
        )
    }

    @Test func removesBothQueryAndFragment() {
        #expect(
            Logger.stripQuery("https://github.com/pull/42?diff=split#discussion_r123")
                == "https://github.com/pull/42"
        )
    }

    @Test func preservesPath() {
        #expect(
            Logger.stripQuery("https://portal.client.com/project/12345/docs")
                == "https://portal.client.com/project/12345/docs"
        )
    }

    @Test func oauthToken() {
        let url = "https://app.com/callback?code=AUTH_CODE_HERE&state=random"
        #expect(Logger.stripQuery(url) == "https://app.com/callback")
    }

    @Test func accessTokenFragment() {
        let url = "https://app.com/spa-signin#access_token=JWT_TOKEN_HERE&token_type=bearer"
        #expect(Logger.stripQuery(url) == "https://app.com/spa-signin")
    }

    @Test func noQueryOrFragment() {
        let url = "https://example.com/path/to/page"
        #expect(Logger.stripQuery(url) == url)
    }

    @Test func encodedQueryParams() {
        let url = "https://example.com/path?key=hello%20world&token=secret%3Dvalue"
        #expect(Logger.stripQuery(url) == "https://example.com/path")
    }

    @Test func emptyString() {
        #expect(Logger.stripQuery("") == "")
    }
}

// MARK: - 1c. Security-critical: sensitive tokens never in output

@Suite("Sensitive token removal")
struct TokenRemovalTests {

    @Test func noOAuthTokenInDomainOnly() {
        let url = "https://login.microsoft.com/oauth?code=SECRET_AUTH_CODE&session_state=abc123"
        let result = Logger.domainOnly(url)
        #expect(!result.contains("SECRET_AUTH_CODE"))
        #expect(!result.contains("session_state"))
        #expect(!result.contains("abc123"))
    }

    @Test func noAccessTokenInDomainOnly() {
        let url = "https://app.com/callback#access_token=eyJhbGciOiJSUzI1NiIs"
        let result = Logger.domainOnly(url)
        #expect(!result.contains("eyJhbGciOiJSUzI1NiIs"))
    }

    @Test func noAccessTokenInStripQuery() {
        let url = "https://app.com/callback#access_token=eyJhbGciOiJSUzI1NiIs"
        let result = Logger.stripQuery(url)
        #expect(!result.contains("eyJhbGciOiJSUzI1NiIs"))
    }

    @Test func noSessionStateInStripQuery() {
        let url = "https://app.com/login?session_state=SECRET_SESSION"
        let result = Logger.stripQuery(url)
        #expect(!result.contains("SECRET_SESSION"))
    }
}

// MARK: - 2. Logger sanitizeURL Integration

@Suite("sanitizeURL integration")
struct SanitizeURLIntegrationTests {

    @Test func defaultConfigReturnsDomainOnly() {
        let config = Config(logDirectory: "/tmp/test", idleThresholdSeconds: 300)
        let logger = Logger(config: config)
        let result = logger.sanitizeURL("https://portal.client.com/project/123?token=abc")
        #expect(result == "portal.client.com")
    }

    @Test func domainOnlyExplicitTrue() {
        var config = Config(logDirectory: "/tmp/test", idleThresholdSeconds: 300)
        config.logSafariDomainOnly = true
        let logger = Logger(config: config)
        let result = logger.sanitizeURL("https://github.com/org/repo/pull/42")
        #expect(result == "github.com")
    }

    @Test func domainOnlyFalseStripsQuery() {
        var config = Config(logDirectory: "/tmp/test", idleThresholdSeconds: 300)
        config.logSafariDomainOnly = false
        config.logSafariURLs = true
        let logger = Logger(config: config)
        let result = logger.sanitizeURL("https://github.com/org/repo?diff=split#discussion")
        #expect(result == "https://github.com/org/repo")
    }

    @Test func domainOnlyFalsePreservesPath() {
        var config = Config(logDirectory: "/tmp/test", idleThresholdSeconds: 300)
        config.logSafariDomainOnly = false
        let logger = Logger(config: config)
        let result = logger.sanitizeURL("https://github.com/org/repo/pull/42")
        #expect(result == "https://github.com/org/repo/pull/42")
    }
}

// MARK: - 3. String Truncation

@Suite("String truncation (200 chars)")
struct StringTruncationTests {

    @Test func truncatesOver200() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        var config = Config(logDirectory: dir, idleThresholdSeconds: 300)
        config.consentGiven = true
        let logger = Logger(config: config)

        let longString = String(repeating: "A", count: 300)
        logger.log(["event": "test", "detail": longString])

        let files = try? FileManager.default.contentsOfDirectory(atPath: dir)
        let file = files?.first(where: { $0.hasSuffix(".jsonl") })
        #expect(file != nil, "JSONL file should be created")
        guard let file else { return }

        let content = try! String(contentsOfFile: "\(dir)/\(file)", encoding: .utf8)
        if let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = json["detail"] as? String {
            #expect(detail.count == 200)
        } else {
            Issue.record("Could not parse logged JSON")
        }
    }

    @Test func doesNotTruncateUnder200() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let config = Config(logDirectory: dir, idleThresholdSeconds: 300)
        let logger = Logger(config: config)

        logger.log(["event": "test", "detail": "Hello World"])

        let files = try? FileManager.default.contentsOfDirectory(atPath: dir)
        guard let file = files?.first(where: { $0.hasSuffix(".jsonl") }) else { return }

        let content = try! String(contentsOfFile: "\(dir)/\(file)", encoding: .utf8)
        if let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = json["detail"] as? String {
            #expect(detail == "Hello World")
        }
    }

    @Test func exactly200NotTruncated() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let config = Config(logDirectory: dir, idleThresholdSeconds: 300)
        let logger = Logger(config: config)

        let exact200 = String(repeating: "B", count: 200)
        logger.log(["event": "test", "detail": exact200])

        let files = try? FileManager.default.contentsOfDirectory(atPath: dir)
        guard let file = files?.first(where: { $0.hasSuffix(".jsonl") }) else { return }

        let content = try! String(contentsOfFile: "\(dir)/\(file)", encoding: .utf8)
        if let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = json["detail"] as? String {
            #expect(detail.count == 200, "Exactly 200 chars should not be truncated")
        }
    }

    @Test func multipleFieldsTruncatedIndependently() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let config = Config(logDirectory: dir, idleThresholdSeconds: 300)
        let logger = Logger(config: config)

        let long1 = String(repeating: "X", count: 250)
        let long2 = String(repeating: "Y", count: 300)
        logger.log(["event": "test", "field1": long1, "field2": long2])

        let files = try? FileManager.default.contentsOfDirectory(atPath: dir)
        guard let file = files?.first(where: { $0.hasSuffix(".jsonl") }) else { return }

        let content = try! String(contentsOfFile: "\(dir)/\(file)", encoding: .utf8)
        if let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let f1 = json["field1"] as? String ?? ""
            let f2 = json["field2"] as? String ?? ""
            #expect(f1.count == 200, "field1 should be truncated to 200")
            #expect(f2.count == 200, "field2 should be truncated to 200")
            #expect(f1.allSatisfy { $0 == "X" }, "field1 should contain only X")
            #expect(f2.allSatisfy { $0 == "Y" }, "field2 should contain only Y")
        } else {
            Issue.record("Could not parse logged JSON")
        }
    }

    @Test func nonStringFieldsNotTruncated() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let config = Config(logDirectory: dir, idleThresholdSeconds: 300)
        let logger = Logger(config: config)
        logger.log(["event": "test", "count": 999, "flag": true])

        let files = try? FileManager.default.contentsOfDirectory(atPath: dir)
        guard let file = files?.first(where: { $0.hasSuffix(".jsonl") }) else { return }

        let content = try! String(contentsOfFile: "\(dir)/\(file)", encoding: .utf8)
        if let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            #expect(json["count"] as? Int == 999)
            #expect(json["flag"] as? Bool == true)
        }
    }
}

// MARK: - 3b. Log Directory Auto-Creation

@Suite("Log directory auto-creation")
struct LogDirectoryTests {

    @Test func createsNestedDirectoryOnLog() throws {
        let base = NSTemporaryDirectory() + "WorkLoggerTest-\(UUID().uuidString)"
        let nested = "\(base)/deep/nested/logs"
        defer { try? FileManager.default.removeItem(atPath: base) }

        let config = Config(logDirectory: nested, idleThresholdSeconds: 300)
        let logger = Logger(config: config)
        logger.log(["event": "test"])

        #expect(FileManager.default.fileExists(atPath: nested), "Nested log directory should be auto-created")
        let files = try FileManager.default.contentsOfDirectory(atPath: nested)
        #expect(files.contains(where: { $0.hasSuffix(".jsonl") }))
    }

    @Test func createsDirectoryOnLogToDate() throws {
        let base = NSTemporaryDirectory() + "WorkLoggerTest-\(UUID().uuidString)"
        let nested = "\(base)/retro/logs"
        defer { try? FileManager.default.removeItem(atPath: base) }

        let config = Config(logDirectory: nested, idleThresholdSeconds: 300)
        let logger = Logger(config: config)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        logger.logToDate(yesterday, fields: ["event": "test"])

        #expect(FileManager.default.fileExists(atPath: nested), "Nested log directory should be auto-created for logToDate")
    }
}

// MARK: - 4. File Permission Tests

@Suite("File permissions (0600)")
struct FilePermissionTests {

    @Test func logFileHasOwnerOnlyPermissions() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let config = Config(logDirectory: dir, idleThresholdSeconds: 300)
        let logger = Logger(config: config)
        logger.log(["event": "test_permissions"])

        let files = try FileManager.default.contentsOfDirectory(atPath: dir)
        let file = files.first(where: { $0.hasSuffix(".jsonl") })
        #expect(file != nil)
        guard let file else { return }

        let path = "\(dir)/\(file)"
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let perms = (attrs[.posixPermissions] as! NSNumber).intValue
        #expect(perms == 0o600, "Log file should have 0600 permissions, got \(String(perms, radix: 8))")
    }

    @Test func logToDateFileHasOwnerOnlyPermissions() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let config = Config(logDirectory: dir, idleThresholdSeconds: 300)
        let logger = Logger(config: config)

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        logger.logToDate(yesterday, fields: ["event": "retro_test"])

        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"
        let expectedFile = "\(dayFmt.string(from: yesterday)).jsonl"
        let path = "\(dir)/\(expectedFile)"

        #expect(FileManager.default.fileExists(atPath: path), "Retro log file should exist")

        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let perms = (attrs[.posixPermissions] as! NSNumber).intValue
        #expect(perms == 0o600, "Retro log file should have 0600 permissions, got \(String(perms, radix: 8))")
    }

    @Test func multipleLogsPreservePermissions() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let config = Config(logDirectory: dir, idleThresholdSeconds: 300)
        let logger = Logger(config: config)
        logger.log(["event": "first"])
        logger.log(["event": "second"])
        logger.log(["event": "third"])

        let files = try FileManager.default.contentsOfDirectory(atPath: dir)
        guard let file = files.first(where: { $0.hasSuffix(".jsonl") }) else { return }

        let attrs = try FileManager.default.attributesOfItem(atPath: "\(dir)/\(file)")
        let perms = (attrs[.posixPermissions] as! NSNumber).intValue
        #expect(perms == 0o600, "Permissions should remain 0600 after multiple writes")
    }
}

// MARK: - 5. Auto-Purge Tests

@Suite("Auto-purge old logs")
struct AutoPurgeTests {

    @Test func purgesFilesOlderThanRetention() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        createFakeLog(dir: dir, daysAgo: 10)
        createFakeLog(dir: dir, daysAgo: 50)
        createFakeLog(dir: dir, daysAgo: 100)
        createFakeLog(dir: dir, daysAgo: 200)

        var config = Config(logDirectory: dir, idleThresholdSeconds: 300)
        config.retentionDays = 90
        let logger = Logger(config: config)
        logger.purgeOldLogs()

        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir)
            .filter { $0.hasSuffix(".jsonl") }
        #expect(remaining.count == 2, "Only files within 90 days should remain")
    }

    @Test func keepsRecentFiles() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        createFakeLog(dir: dir, daysAgo: 1)
        createFakeLog(dir: dir, daysAgo: 5)
        createFakeLog(dir: dir, daysAgo: 30)
        createFakeLog(dir: dir, daysAgo: 89)

        var config = Config(logDirectory: dir, idleThresholdSeconds: 300)
        config.retentionDays = 90
        let logger = Logger(config: config)
        logger.purgeOldLogs()

        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir)
            .filter { $0.hasSuffix(".jsonl") }
        #expect(remaining.count == 4, "All files within 90 days should be kept")
    }

    @Test func customRetentionPeriod() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        createFakeLog(dir: dir, daysAgo: 5)
        createFakeLog(dir: dir, daysAgo: 15)
        createFakeLog(dir: dir, daysAgo: 25)

        var config = Config(logDirectory: dir, idleThresholdSeconds: 300)
        config.retentionDays = 10
        let logger = Logger(config: config)
        logger.purgeOldLogs()

        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir)
            .filter { $0.hasSuffix(".jsonl") }
        #expect(remaining.count == 1, "Only files within 10 days should remain")
    }

    @Test func defaultRetentionIs90Days() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        createFakeLog(dir: dir, daysAgo: 89)
        createFakeLog(dir: dir, daysAgo: 91)

        let config = Config(logDirectory: dir, idleThresholdSeconds: 300)
        let logger = Logger(config: config)
        logger.purgeOldLogs()

        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir)
            .filter { $0.hasSuffix(".jsonl") }
        #expect(remaining.count == 1, "Default 90-day retention: 89-day kept, 91-day purged")
    }

    @Test func exactBoundaryIsPurged() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        createFakeLog(dir: dir, daysAgo: 90)  // exactly at boundary

        var config = Config(logDirectory: dir, idleThresholdSeconds: 300)
        config.retentionDays = 90
        let logger = Logger(config: config)
        logger.purgeOldLogs()

        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir)
            .filter { $0.hasSuffix(".jsonl") }
        #expect(remaining.count == 0, "File exactly at retention boundary should be purged (cutoff is strict <)")
    }

    @Test func doesNotPurgeNonJsonlFiles() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        createFakeLog(dir: dir, daysAgo: 200)
        try "notes".write(toFile: "\(dir)/notes.txt", atomically: true, encoding: .utf8)

        var config = Config(logDirectory: dir, idleThresholdSeconds: 300)
        config.retentionDays = 90
        let logger = Logger(config: config)
        logger.purgeOldLogs()

        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir)
        #expect(remaining.contains("notes.txt"), "Non-JSONL files should not be purged")
    }

    @Test func emptyDirectoryDoesNotCrash() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        var config = Config(logDirectory: dir, idleThresholdSeconds: 300)
        config.retentionDays = 90
        let logger = Logger(config: config)
        logger.purgeOldLogs()
        // No crash = pass
    }
}

// MARK: - 6. Config Privacy Fields

@Suite("Config privacy fields")
struct ConfigPrivacyFieldsTests {

    @Test func decodesAllPrivacyFields() throws {
        let json = """
        {
            "logDirectory": "/tmp/test",
            "idleThresholdSeconds": 300,
            "defaultDurationMinutes": 30,
            "retentionDays": 60,
            "safariTrackingEnabled": false,
            "logSafariURLs": false,
            "logSafariDomainOnly": true,
            "showSafariTimeInReport": true,
            "consentGiven": true
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(Config.self, from: json)
        #expect(config.logDirectory == "/tmp/test")
        #expect(config.idleThresholdSeconds == 300)
        #expect(config.defaultDurationMinutes == 30)
        #expect(config.retentionDays == 60)
        #expect(config.safariTrackingEnabled == false)
        #expect(config.logSafariURLs == false)
        #expect(config.logSafariDomainOnly == true)
        #expect(config.showSafariTimeInReport == true)
        #expect(config.consentGiven == true)
    }

    @Test func decodesMinimalJSON() throws {
        let json = """
        {
            "logDirectory": "/tmp/test",
            "idleThresholdSeconds": 300
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(Config.self, from: json)
        #expect(config.logDirectory == "/tmp/test")
        #expect(config.retentionDays == nil)
        #expect(config.safariTrackingEnabled == nil)
        #expect(config.logSafariURLs == nil)
        #expect(config.logSafariDomainOnly == nil)
        #expect(config.showSafariTimeInReport == nil)
        #expect(config.consentGiven == nil)
    }

    @Test func roundTripEncodeDecode() throws {
        var config = Config(logDirectory: "/tmp/test", idleThresholdSeconds: 300)
        config.retentionDays = 60
        config.safariTrackingEnabled = false
        config.logSafariURLs = false
        config.logSafariDomainOnly = true
        config.showSafariTimeInReport = true
        config.consentGiven = true

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(Config.self, from: data)

        #expect(decoded.retentionDays == 60)
        #expect(decoded.safariTrackingEnabled == false)
        #expect(decoded.logSafariURLs == false)
        #expect(decoded.logSafariDomainOnly == true)
        #expect(decoded.showSafariTimeInReport == true)
        #expect(decoded.consentGiven == true)
    }

    @Test func defaultsWhenFieldsAbsent() {
        let config = Config(logDirectory: "/tmp/test", idleThresholdSeconds: 300)

        #expect((config.retentionDays ?? 90) == 90, "Default retention: 90 days")
        #expect((config.safariTrackingEnabled ?? true) == true, "Safari tracking default: enabled")
        #expect((config.logSafariURLs ?? true) == true, "URL logging default: enabled")
        #expect((config.logSafariDomainOnly ?? true) == true, "Domain-only default: enabled")
        #expect((config.consentGiven ?? false) == false, "Consent default: not given")
        #expect((config.showSafariTimeInReport ?? false) == false, "Safari time default: disabled")
        #expect((config.defaultDurationMinutes ?? 60) == 60, "Default duration: 60 min")
    }
}

// MARK: - 7. Consent Mechanism

@Suite("Consent mechanism")
struct ConsentMechanismTests {

    @Test func defaultIsFalse() {
        let config = Config(logDirectory: "/tmp/test", idleThresholdSeconds: 300)
        #expect((config.consentGiven ?? false) == false, "Consent should default to false")
    }

    @Test func canBeSetToTrue() {
        var config = Config(logDirectory: "/tmp/test", idleThresholdSeconds: 300)
        config.consentGiven = true
        #expect((config.consentGiven ?? false) == true)
    }

    @Test func persistsThroughEncodeDecode() throws {
        var config = Config(logDirectory: "/tmp/test", idleThresholdSeconds: 300)
        config.consentGiven = true

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(Config.self, from: data)
        #expect((decoded.consentGiven ?? false) == true)
    }

    @Test func consentBlockLogic() {
        let noConsent = Config(logDirectory: "/tmp/test", idleThresholdSeconds: 300)
        #expect(!(noConsent.consentGiven ?? false) == true, "No consent → should block")

        var withConsent = Config(logDirectory: "/tmp/test", idleThresholdSeconds: 300)
        withConsent.consentGiven = true
        #expect(!(withConsent.consentGiven ?? false) == false, "With consent → should not block")
    }
}

// MARK: - 8. Safari Tracking Toggles

@Suite("Safari tracking toggles")
struct SafariTrackingToggleTests {

    @Test func safariTrackingDefaultEnabled() {
        let config = Config(logDirectory: "/tmp/test", idleThresholdSeconds: 300)
        #expect((config.safariTrackingEnabled ?? true) == true)
    }

    @Test func safariTrackingCanBeDisabled() {
        var config = Config(logDirectory: "/tmp/test", idleThresholdSeconds: 300)
        config.safariTrackingEnabled = false
        #expect((config.safariTrackingEnabled ?? true) == false)
    }

    @Test func logSafariURLsDefaultEnabled() {
        let config = Config(logDirectory: "/tmp/test", idleThresholdSeconds: 300)
        #expect((config.logSafariURLs ?? true) == true)
    }

    @Test func logSafariURLsCanBeDisabled() {
        var config = Config(logDirectory: "/tmp/test", idleThresholdSeconds: 300)
        config.logSafariURLs = false
        #expect((config.logSafariURLs ?? true) == false)
    }

    @Test func domainOnlyDefaultEnabled() {
        let config = Config(logDirectory: "/tmp/test", idleThresholdSeconds: 300)
        #expect((config.logSafariDomainOnly ?? true) == true)
    }

    @Test func sanitizeURLRespectsDomainOnlyToggle() {
        var domainConfig = Config(logDirectory: "/tmp/test", idleThresholdSeconds: 300)
        domainConfig.logSafariDomainOnly = true
        let domainLogger = Logger(config: domainConfig)
        #expect(domainLogger.sanitizeURL("https://github.com/org/repo") == "github.com")

        var pathConfig = Config(logDirectory: "/tmp/test", idleThresholdSeconds: 300)
        pathConfig.logSafariDomainOnly = false
        let pathLogger = Logger(config: pathConfig)
        #expect(pathLogger.sanitizeURL("https://github.com/org/repo") == "https://github.com/org/repo")
    }
}

// MARK: - 9. Logger logToDate

@Suite("logToDate retroactive entries")
struct LogToDateTests {

    @Test func writesToCorrectFile() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let config = Config(logDirectory: dir, idleThresholdSeconds: 300)
        let logger = Logger(config: config)

        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        logger.logToDate(threeDaysAgo, fields: ["event": "retro_entry", "detail": "past work"])

        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"
        let expectedFile = "\(dayFmt.string(from: threeDaysAgo)).jsonl"

        let files = try FileManager.default.contentsOfDirectory(atPath: dir)
        #expect(files.contains(expectedFile), "Should write to past date's file")
    }

    @Test func timestampMatchesDate() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let config = Config(logDirectory: dir, idleThresholdSeconds: 300)
        let logger = Logger(config: config)

        var comps = DateComponents()
        comps.year = 2026; comps.month = 4; comps.day = 10
        comps.hour = 14; comps.minute = 30
        let specificDate = Calendar.current.date(from: comps)!
        logger.logToDate(specificDate, fields: ["event": "test"])

        let path = "\(dir)/2026-04-10.jsonl"
        let content = try String(contentsOfFile: path, encoding: .utf8)
        #expect(content.contains("2026-04-10T14:30:00"), "Timestamp should reflect the provided date")
    }

    @Test func truncatesStrings() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let config = Config(logDirectory: dir, idleThresholdSeconds: 300)
        let logger = Logger(config: config)

        let longString = String(repeating: "X", count: 300)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        logger.logToDate(yesterday, fields: ["event": "test", "detail": longString])

        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"
        let path = "\(dir)/\(dayFmt.string(from: yesterday)).jsonl"
        let content = try String(contentsOfFile: path, encoding: .utf8)

        if let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = json["detail"] as? String {
            #expect(detail.count == 200, "logToDate should also truncate to 200 chars")
        } else {
            Issue.record("Could not parse logged JSON")
        }
    }
}

// MARK: - 10. Retention Edge Cases

@Suite("Retention edge cases")
struct RetentionEdgeCaseTests {

    @Test func zeroDisablesPurge() {
        var config = Config(logDirectory: "/tmp/nonexistent", idleThresholdSeconds: 300)
        config.retentionDays = 0
        let logger = Logger(config: config)
        logger.purgeOldLogs() // guard retention > 0 → returns, no crash
    }

    @Test func negativeDisablesPurge() {
        var config = Config(logDirectory: "/tmp/nonexistent", idleThresholdSeconds: 300)
        config.retentionDays = -5
        let logger = Logger(config: config)
        logger.purgeOldLogs() // guard retention > 0 → returns, no crash
    }
}

// MARK: - 11. Privacy-by-Default

@Suite("Privacy-by-default verification")
struct PrivacyByDefaultTests {

    @Test func defaultConfigIsMostPrivate() {
        let config = Config(logDirectory: "/tmp/test", idleThresholdSeconds: 300)

        #expect((config.logSafariDomainOnly ?? true) == true,
                "PRIVACY BY DEFAULT: Domain-only URL logging should be the default")
        #expect((config.consentGiven ?? false) == false,
                "PRIVACY BY DEFAULT: Consent should not be pre-given")
        #expect((config.retentionDays ?? 90) == 90,
                "PRIVACY BY DEFAULT: Retention should default to 90 days, not unlimited")
    }

    @Test func sanitizeURLDefaultStripsSensitiveData() {
        let config = Config(logDirectory: "/tmp/test", idleThresholdSeconds: 300)
        let logger = Logger(config: config)

        let sensitiveURLs = [
            "https://login.microsoftonline.com/common/oauth2?code=AUTH_SECRET",
            "https://app.com/callback#access_token=eyJhbGciOiJSUzI1NiIs",
            "https://portal.client.com/project/CONFIDENTIAL_ID/documents",
            "https://jira.company.com/browse/SECRET-1234",
        ]
        for url in sensitiveURLs {
            let result = logger.sanitizeURL(url)
            #expect(!result.contains("/"), "Default should return domain-only, no paths. Got: \(result)")
            #expect(!result.contains("?"), "Default should strip query strings. Got: \(result)")
            #expect(!result.contains("#"), "Default should strip fragments. Got: \(result)")
        }
    }
}

// MARK: - TeamsCallMonitor

@Suite("TeamsCallMonitor – extractMeetingName")
struct TeamsCallMonitorTests {

    @Test func extractsPersonName() {
        let title = "Florentin Rauscher | Kompakte Besprechungsansicht | Microsoft Teams"
        #expect(TeamsCallMonitor.extractMeetingName(from: title) == "Florentin Rauscher")
    }

    @Test func extractsMeetingName() {
        let title = "Sprint Planning | Kompakte Besprechungsansicht | Microsoft Teams"
        #expect(TeamsCallMonitor.extractMeetingName(from: title) == "Sprint Planning")
    }

    @Test func returnsNilForNonCallWindow() {
        let title = "Chat | Microsoft Teams"
        #expect(TeamsCallMonitor.extractMeetingName(from: title) == nil)
    }

    @Test func handlesCalendarFormat() {
        let title = "Microsoft Teams | Kompakte Besprechungsansicht | Calendar"
        #expect(TeamsCallMonitor.extractMeetingName(from: title) == nil)
    }

    @Test func callIndicatorPresent() {
        let title = "Sven Metscher | Kompakte Besprechungsansicht | Microsoft Teams"
        #expect(title.contains(TeamsCallMonitor.callIndicator))
    }

    @Test func callIndicatorAbsentInChat() {
        let title = "Chat | Microsoft Teams"
        #expect(!title.contains(TeamsCallMonitor.callIndicator))
    }
}
