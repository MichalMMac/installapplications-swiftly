//
//  JSONControllItem.swift
//  installapplications-swiftly
//
//  2021 Michal Moravec
//

import Foundation

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
