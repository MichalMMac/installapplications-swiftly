//
//  File.swift
//  installapplications-swiftly
//
//  2021 Michal Moravec
//

import Foundation

class RootScript: DeployItem {

    override var filePermissions: Int { 0o700 }

    override func execute() {
        ias.reporter.beginStep(name: "Running system script: \(self.name)")

        guard executeCommon() else {
            return
        }

        if settings.dryRun {
            logger.log("\(self.name, privacy: .public): Dry run executing root script \(self.filePath, privacy: .public)")
        } else {
            logger.log("\(self.name, privacy: .public): Initiating root script \(self.filePath, privacy: .public)")
            let task = Process()
            task.executableURL = fileURL
            returnCode = executeProcess(task: task, logger: logger, async: async)
        }
        if returnCode != 0 {
            self.logger.error("\(self.name, privacy: .public) Root script exited with non zero code \(self.returnCode, privacy: .public)")
        }
        state = (returnCode == 0 ? .finished : .failed)
    }
}
