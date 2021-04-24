//
//  File.swift
//  iasd
//
//  Created by michal on 19.03.2021.
//

import Foundation
import os

extension UserDefaults {

    public func optionalInt(forKey defaultName: String) -> Int? {
        let defaults = self
        if let value = defaults.value(forKey: defaultName) {
            return value as? Int
        }
        return nil
    }

    public func optionalBool(forKey defaultName: String) -> Bool? {
        let defaults = self
        if let value = defaults.value(forKey: defaultName) {
            return value as? Bool
        }
        return nil
    }
}

enum HashCheckPolicy: String, Decodable {
    case ignore = "Ignore"
    case warning = "Warning"
    case strict = "Strict"
    case invalid = "Invalid"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let status = try? container.decode(String.self)
        self.init(string: status)
    }

    init(string: String?) {
        switch string {
            case "Ignore": self = .ignore
            case "Warning": self = .warning
            case "Strict": self = .strict
        default:
            self = .invalid
        }
    }
}

struct SettingFile: Decodable {

    enum CodingKeys: String, CodingKey {
        case DEPNotifyEnable = "DEPNotifyEnable"
        case DEPNotifyControlFile = "DEPNotifyControlFile"
        case DEPNotifyDeterminate = "DEPNotifyDeterminate"
        case dryRun = "DryRun"
        case hashCheckPolicy = "HashCheckPolicy"
        case iasPath = "InstallPath"
        case launchDaemonIdentifier = "LaunchDaemonIdentifier"
        case launchAgentIdentifier = "LaunchAgentIdentifier"
        case identifier = "Identifier"
        case minDownloadConcurrency = "MinDownloadConcurrency"
        case maxDownloadConcurrency = "MaxDownloadConcurrency"
        case reboot = "Reboot"
        case redownloads = "MaximumRedownloads"
        case skipJSONValidation = "SkipJSONValidation"
        case waitForAgentTimeout = "WaitForAgentTimeout"
        case httpAuthPassword = "HTTPAuthPassword"
        case httpAuthUser = "HTTPAuthUser"
        case jsonURL = "JSONURL"
    }

    let DEPNotifyEnable: Bool?
    let DEPNotifyControlFile: String?
    let DEPNotifyDeterminate: Bool?
    let dryRun: Bool?
    let hashCheckPolicy: HashCheckPolicy
    let iasPath: String?
    let identifier: String?
    let launchDaemonIdentifier: String?
    let launchAgentIdentifier: String?
    let minDownloadConcurrency: Int?
    let maxDownloadConcurrency: Int?
    let reboot: Bool?
    let redownloads: Int?
    let skipJSONValidation: Bool?
    let waitForAgentTimeout: Int?
    let jsonURL: String?
    let httpAuthPassword: String?
    let httpAuthUser: String?
}

class Settings {
    var DEPNotifyEnable = false
    var DEPNotifyControlFile = URL(fileURLWithPath: "/var/tmp/depnotify.log")
    var DEPNotifyDeterminate = true
    var dryRun = false
    var hashCheckPolicy = HashCheckPolicy.strict
    var iasPath = URL(fileURLWithPath: defaultInstallPath)
    var identifier = defaultIdentifier
    var launchDaemonIdentifier = defaultDaemonIdentifier
    var launchAgentIdentifier = defaultAgentIdentifier
    var minDownloadConcurrency = 1
    var maxDownloadConcurrency = 4
    var reboot = false
    var redownloads = 3
    var skipJSONValidation = false
    var waitForAgentTimeout = 86400

    var jsonURL: URL?
    var httpAuthPassword: String?
    var httpAuthUser: String?

    let logger: Logger

    enum SettingSource: String {
        case none = "not set"
        case preconfigured = "default value"
        case argument = "command line argument"
        case file = "configuration file"
        case defaults = "macOS UserDefaults"
    }

    var DEPNotifyEnableSource = SettingSource.preconfigured
    var DEPNotifyControlFileSource = SettingSource.preconfigured
    var DEPNotifyDeterminateSource = SettingSource.preconfigured
    var dryRunSource = SettingSource.preconfigured
    var hashCheckPolicySource = SettingSource.preconfigured
    var iasPathSource = SettingSource.preconfigured
    var identifierSource = SettingSource.preconfigured
    var launchDaemonIdentifierSource = SettingSource.preconfigured
    var launchAgentIdentifierSource = SettingSource.preconfigured
    var minDownloadConcurrencySource = SettingSource.preconfigured
    var maxDownloadConcurrencySource = SettingSource.preconfigured
    var rebootSource = SettingSource.preconfigured
    var redownloadsSource = SettingSource.preconfigured
    var skipJSONValidationSource = SettingSource.preconfigured
    var waitForAgentTimeoutSource = SettingSource.preconfigured
    var jsonURLSource = SettingSource.none
    var httpAuthPasswordSource = SettingSource.none
    var httpAuthUserSource = SettingSource.none


    init() {
        logger = Logger(subsystem: identifier, category: "settings")

        loadSettingsFromUserDefaults()

        // Override with settings from the settings file
        loadSettingFromFile()

        // TODO? Override with setting from args

        printSettings()
    }

    func printSettings() {
        logger.debug("DEPNotifyEnable: \(self.DEPNotifyEnable, privacy: .public) Source: \(self.DEPNotifyEnableSource.rawValue, privacy: .public)")
        logger.debug("DEPNotifyControlFile: \(self.DEPNotifyControlFile, privacy: .public) Source: \(self.DEPNotifyControlFileSource.rawValue, privacy: .public)")
        logger.debug("DEPNotifyDeterminate: \(self.DEPNotifyDeterminate, privacy: .public) Source: \(self.DEPNotifyDeterminateSource.rawValue, privacy: .public)")
        logger.debug("HashCheckPolicy: \(self.hashCheckPolicy.rawValue, privacy: .public) Source: \(self.hashCheckPolicySource.rawValue, privacy: .public)")
        logger.debug("HTTPAuthPassword: <REDACTED> Source: \(self.httpAuthPasswordSource.rawValue, privacy: .public)")
        logger.debug("HTTPAuthUser: <REDACTED> Source: \(self.httpAuthUserSource.rawValue, privacy: .public)")
        logger.debug("JSONURL: \(self.jsonURL?.absoluteString ?? "") Source: \(self.jsonURLSource.rawValue, privacy: .public)")
        logger.debug("Identifier: \(self.identifier, privacy: .public) Source: \(self.identifierSource.rawValue, privacy: .public)")
        logger.debug("LaunchAgentIdentifier: \(self.launchAgentIdentifier, privacy: .public) Source: \(self.launchAgentIdentifierSource.rawValue, privacy: .public)")
        logger.debug("LaunchDaemonIdentifier: \(self.launchDaemonIdentifier, privacy: .public) Source: \(self.launchDaemonIdentifierSource.rawValue, privacy: .public)")
        logger.debug("MinDownloadConcurrency: \(self.minDownloadConcurrency, privacy: .public) Source: \(self.minDownloadConcurrencySource.rawValue, privacy: .public)")
        logger.debug("MaxDownloadConcurrency: \(self.maxDownloadConcurrency, privacy: .public) Source: \(self.maxDownloadConcurrencySource.rawValue, privacy: .public)")
        logger.debug("MaximumRedownloads: \(self.redownloads, privacy: .public) Source: \(self.redownloadsSource.rawValue, privacy: .public)")
        logger.debug("Reboot: \(self.reboot, privacy: .public) Source: \(self.rebootSource.rawValue, privacy: .public)")
        logger.debug("SkipJSONValidation: \(self.skipJSONValidation, privacy: .public) Source: \(self.skipJSONValidationSource.rawValue, privacy: .public)")
        logger.debug("WaitForAgentTimeout: \(self.waitForAgentTimeout, privacy: .public) Source: \(self.waitForAgentTimeoutSource.rawValue, privacy: .public)")
    }

    func loadSettingFromFile() {
        let configFile: URL
        let arguments = CommandLine.arguments
        let settingsFromFile: SettingFile

        if arguments.count > 1 {
            configFile = URL(fileURLWithPath: arguments[1])
            logger.debug("Got config file path via argument: \(configFile.path)")
        } else {
            configFile = URL(fileURLWithPath: arguments[0]).deletingLastPathComponent().appendingPathComponent(daemonConfigFileName)
        }

        logger.debug("Attempting to load setting from config file at path: \(configFile.path, privacy: .public)")

        guard FileManager.default.fileExists(atPath: configFile.path) else {
            logger.info("No config file present")
            return
        }

        do {
            let configFileContents = try Data(contentsOf: configFile)
            settingsFromFile = try PropertyListDecoder().decode(SettingFile.self, from: configFileContents)
        } catch {
            logger.error("Unable to parse config file")
            return
        }
        if let value = settingsFromFile.DEPNotifyEnable {
            DEPNotifyEnable = value
            DEPNotifyEnableSource = .file
        }
        if let value = settingsFromFile.DEPNotifyControlFile {
            DEPNotifyControlFile = URL(fileURLWithPath: value)
            DEPNotifyControlFileSource = .file
        }
        if let value = settingsFromFile.DEPNotifyDeterminate {
            DEPNotifyDeterminate = value
            DEPNotifyDeterminateSource = .file
        }
        if let value = settingsFromFile.dryRun {
            dryRun = value
            dryRunSource = .file
        }
        if let value = settingsFromFile.httpAuthUser {
            httpAuthUser = value
            httpAuthUserSource = .file
        }
        if let value = settingsFromFile.httpAuthPassword {
            httpAuthPassword = value
            httpAuthPasswordSource = .file
        }
        if settingsFromFile.hashCheckPolicy != .invalid {
            hashCheckPolicy = settingsFromFile.hashCheckPolicy
            hashCheckPolicySource = .file
        }
        if let value = settingsFromFile.iasPath {
            iasPath = URL(fileURLWithPath: value)
            iasPathSource = .file
        }
        if let value = settingsFromFile.jsonURL {
            jsonURL = URL(string: value)
            jsonURLSource = .file
        }
        if let value = settingsFromFile.launchDaemonIdentifier {
            launchDaemonIdentifier = value
            launchDaemonIdentifierSource = .file
        }
        if let value = settingsFromFile.launchAgentIdentifier {
            launchAgentIdentifier = value
            launchAgentIdentifierSource = .file
        }
        if let value = settingsFromFile.identifier {
            identifier = value
            identifierSource = .file
        }
        if let value = settingsFromFile.minDownloadConcurrency {
            minDownloadConcurrency = value
            minDownloadConcurrencySource = .file
        }
        if let value = settingsFromFile.maxDownloadConcurrency {
            maxDownloadConcurrency = value
            maxDownloadConcurrencySource = .file
        }
        if let value = settingsFromFile.reboot {
            reboot = value
            rebootSource = .file
        }
        if let value = settingsFromFile.redownloads {
            redownloads = value
            redownloadsSource = .file
        }
        if let value = settingsFromFile.skipJSONValidation {
            skipJSONValidation = value
            skipJSONValidationSource = .file
        }
        if let value = settingsFromFile.waitForAgentTimeout {
            waitForAgentTimeout = value
            waitForAgentTimeoutSource = .file
        }

    }

    func loadSettingsFromUserDefaults() {
        logger.debug("Attempting to load setting from UserDefaults domain: \(defaultDaemonIdentifier, privacy: .public)")
        if let defaults = UserDefaults(suiteName: defaultDaemonIdentifier) {
            if let value = defaults.optionalBool(forKey: "DEPNotifyEnable") {
                DEPNotifyEnable = value
                DEPNotifyEnableSource = .defaults
            }
            if let value = defaults.string(forKey: "DEPNotifyControlFile") {
                DEPNotifyControlFile = URL(fileURLWithPath: value)
                DEPNotifyControlFileSource = .defaults
            }
            if let value = defaults.optionalBool(forKey: "DEPNotifyDeterminate") {
                DEPNotifyDeterminate = value
                DEPNotifyDeterminateSource = .defaults
            }
            if let value = defaults.optionalBool(forKey: "DryRun") {
                dryRun = value
                dryRunSource = .defaults
            }
            if let value = defaults.string(forKey: "HashCheckPolicy") {
                let policy = HashCheckPolicy(string: value)
                if policy != .invalid {
                    hashCheckPolicy = policy
                    hashCheckPolicySource = .defaults
                }
            }
            if let value = defaults.string(forKey: "HTTPAuthPassword") {
                httpAuthPassword = value
                httpAuthPasswordSource = .defaults
            }
            if let value = defaults.string(forKey: "HTTPAuthUser") {
                httpAuthUser = value
                httpAuthUserSource = .defaults
            }

            if let value = defaults.string(forKey: "Identifier") {
                identifier = value
                identifierSource = .defaults
            }
            if let value = defaults.string(forKey: "InstallPath") {
                iasPath = URL(fileURLWithPath: value)
                iasPathSource = .defaults
            }
            if let value = defaults.string(forKey: "JSONURL") {
                jsonURL = URL(string: value)
                jsonURLSource = .defaults
            }
            if let value = defaults.string(forKey: "LaunchDaemonIdentifier") {
                launchDaemonIdentifier = value
                launchDaemonIdentifierSource = .defaults
            }
            if let value = defaults.string(forKey: "LaunchAgentIdentifier") {
                launchAgentIdentifier = value
                launchAgentIdentifierSource = .defaults
            }
            if let value = defaults.optionalInt(forKey: "MinDownloadConcurrency") {
                minDownloadConcurrency = value
                minDownloadConcurrencySource = .defaults
            }
            if let value = defaults.optionalInt(forKey: "MaxDownloadConcurrency") {
                maxDownloadConcurrency = value
                maxDownloadConcurrencySource = .defaults
            }
            if let value = defaults.optionalInt(forKey: "MaximumRedownloads") {
                redownloads = value
                redownloadsSource = .defaults
            }
            if let value = defaults.optionalBool(forKey: "Reboot") {
                reboot = value
                rebootSource = .defaults
            }
            if let value = defaults.optionalBool(forKey: "SkipJSONValidation") {
                skipJSONValidation = value
                skipJSONValidationSource = .defaults
            }
            if let value = defaults.optionalInt(forKey: "WaitForAgentTimeout") {
                waitForAgentTimeout = value
                waitForAgentTimeoutSource = .defaults
            }
        } else {
            logger.debug("Unable to access UserDefaults settings")
        }
    }

    func check() {
        guard jsonURL != nil else {
            logger.error("Unable to continue! Missing JSONURL setting")
            ias.finish()
            exit(1)
        }
    }
}
