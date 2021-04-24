//
//  JSONControllItem.swift
//  installapplications-swiftly
//
//  2021 Michal Moravec
//

import Foundation

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

    func totalItemCount() -> Int {
        return (preflight?.count ?? 0) + (setupassistant?.count ?? 0) + (userland?.count ?? 0)
    }
}

class JSONControlItem : DeployItem {

    func parse() -> JsonLists {

        var jsonData: Data?

        do {
            jsonData = try Data(contentsOf: fileURL)
        } catch {
            logger.error("\(self.name): Unable to load JSON from file")
            ias.finish()
            exit(1)
        }

        let decoder = JSONDecoder()
        let decodedData: JsonLists

        do {
            decodedData = try decoder.decode(JsonLists.self, from: jsonData!)
        } catch {
            logger.error("\(self.name, privacy: .public): Unable to parse JSON: \(String(describing: error), privacy: .public)")
            ias.finish()
            exit(1)
        }
        state = .finished
        return decodedData
    }

    override func execute() {
        guard executeCommon() else {
            logger.error("\(self.name, privacy: .public): Getting JSON control failed. Exiting")
            ias.finish()
            exit(1)
        }
    }

    // No hash checking for JSON control item
    override func checkDownload(failed: Bool = false) {
        if failed {
            reDownload()
        } else {
            approveDownload()
        }
    }
}
