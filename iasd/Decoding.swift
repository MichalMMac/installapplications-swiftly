//
//  Decoding.swift
//  installapplications-swiftly
//
//  2021 Michal Moravec
//

import Foundation
import os

// Parsing pkgutil plist output
struct pkgInfoPlist: Decodable {
    enum CodingKeys: String, CodingKey {
        case pkgVersion = "pkg-version"
    }
    let pkgVersion: String
}

// Parsing JSON control item
enum ItemType: String, Decodable {
    case package = "package"
    case rootScript = "rootscript"
    case userScript = "usercript"
    case unknown = "unknown"
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let status = try? container.decode(String.self)
        switch status {
            case "package": self = .package
            case "rootscript": self = .rootScript
            case "userscript": self = .userScript
        default:
            self = .unknown
        }
    }
}

enum ItemFailPolicy: Decodable {
    case failable, failableExecution, failureIsNotAnOption
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let status = try? container.decode(String.self)
        switch status {
            case "failable": self = .failable
            case "failable_execution": self = .failableExecution
            case "failure_is_not_an_option": self = .failureIsNotAnOption
        default:
            self = .failableExecution
        }
    }
}

struct JsonItem: Decodable {

    enum CodingKeys: String, CodingKey {
        case donotwait = "donotwait"
        case file = "file"
        case hash = "hash"
        case name = "name"
        case type = "type"
        case url = "url"
        case packageID = "packageid"
        case pkgRequired = "pkg_required"
        case parallelGroup = "parallel_group"
        case version = "version"
        case _failPolicy = "fail_policy"
    }

    private let _failPolicy: ItemFailPolicy?

    let donotwait: Bool?
    let file: String
    let hash: String?
    let name: String
    let url: String?
    let packageID: String?
    let pkgRequired: Bool?
    let parallelGroup: String?
    let version: String?
    var type: ItemType
    var failPolicy: ItemFailPolicy { return _failPolicy ?? ItemFailPolicy.failableExecution }
}

struct JsonLists: Decodable {
    let preflight: [JsonItem]?
    let setupassistant: [JsonItem]?
    let userland: [JsonItem]?
}

// Parsing ias Plist configuration file
enum HashCheckPolicy: Decodable {
    case ignore, warning, strict

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let status = try? container.decode(String.self)
        switch status {
            case "Ignore": self = .ignore
            case "Warning": self = .warning
            case "Strict": self = .strict
        default:
            self = .strict
        }
    }
}

struct Options: Decodable {

    enum CodingKeys: String, CodingKey {
        case _dryRun = "DryRun"
        case _hashCheckPolicy = "HashCheckPolicy"
        case _iasPath = "IASPath"
        case _launchDaemonIdentifier = "LaunchDaemonIdentifier"
        case _launchAgentIdentifier = "LaunchAgentIdentifier"
        case _identifier = "Identifier"
        case _minDownloadConcurrency = "MinimumDownloadConcurrency"
        case _maxDownloadConcurrency = "MaximumDownloadConcurrency"
        case _reboot = "Reboot"
        case _redownloads = "MaximumRedownloads"
        case _skipJSONValidation = "SkipJSONValidation"
        case _waitForAgentTimeout = "WaitForAgentTimeout"
        case httpAuthPassword = "HTTPAuthPassword"
        case httpAuthUser = "HTTPAuthUser"
        case jsonURL = "JSONURL"
    }

    private var _dryRun: Bool?
    private var _hashCheckPolicy: HashCheckPolicy?
    private var _iasPath: String?
    private var _identifier: String?
    private var _launchDaemonIdentifier: String?
    private var _launchAgentIdentifier: String?
    private var _minDownloadConcurrency: Int?
    private var _maxDownloadConcurrency: Int?
    private var _reboot: Bool?
    private var _redownloads: Int?
    private var _skipJSONValidation: Bool?
    private var _waitForAgentTimeout: Int?

    var jsonURL: String
    var httpAuthPassword: String?
    var httpAuthUser: String?

    var dryRun: Bool { return _dryRun ?? false }
    var hashCheckPolicy: HashCheckPolicy { return _hashCheckPolicy ?? HashCheckPolicy.strict }
    var iasPath: String { return _iasPath ?? "/Library/installapplications" }
    var identifier: String { return _identifier ?? defaultIdentifier }
    var launchDaemonIdentifier: String { return _launchDaemonIdentifier ?? defaultDaemonIdentifier }
    var launchAgentIdentifier: String { return _launchAgentIdentifier ?? defaultAgentIdentifier }
    var minDownloadConcurrency: Int { return _minDownloadConcurrency ?? 1 }
    var maxDownloadConcurrency: Int { return _maxDownloadConcurrency ?? 4 }
    var reboot: Bool { return _reboot ?? false }
    var redownloads: Int { return _redownloads ?? 3 }
    var skipJSONValidation: Bool { return _skipJSONValidation ?? false }
    var waitForAgentTimeout: Int { return _waitForAgentTimeout ?? 86400 }
}

func loadOptions(fromFile configFile: URL) -> Options {
    let options: Options?
    let logger = Logger(subsystem: defaultIdentifier, category: "main")
    do {
        let configFileContents = try Data(contentsOf: configFile)
        options = try PropertyListDecoder().decode(Options.self, from: configFileContents)
    } catch {
        logger.error("Error loading options from file: \(String(describing: error.localizedDescription), privacy: .public)")
        exit(1)
    }
    return options!
}
