//
//  Userscript.swift
//  installapplications-swiftly
//
//  2021 Michal Moravec
//

import Foundation

class UserScript: DeployItem {

    override var filePermissions: Int { 0o755 }

    override func execute() {
        guard executeCommon() else {
            return
        }

        if ias.options.dryRun {
            logger.log("\(self.name, privacy: .public): Dry run executing user script \(self.filePath, privacy: .public)")
        } else {
            returnCode = ias.xpcServer!.runUserScript(scriptURL: fileURL, async: async)
        }
        if returnCode != 0 {
            logger.error("\(self.name, privacy: .public) User script exited with non zero code \(self.returnCode, privacy: .public)")
        }
        state = (returnCode == 0 ? .finished : .failed)
    }
}
