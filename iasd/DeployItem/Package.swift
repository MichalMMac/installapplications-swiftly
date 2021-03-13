//
//  Package.swift
//  installapplications-swiftly
//
//  2021 Michal Moravec
//

import Foundation

class Package: DeployItem {

    let version: String?
    let packageID: String?
    let packageRequired: Bool

    override var filePermissions: Int { 0o600 }

    override init(_ itemConfig: JsonItem) {
        packageID = itemConfig.packageID
        packageRequired = itemConfig.pkgRequired ?? false
        version = itemConfig.version
        super.init(itemConfig)
    }

    func checkReceipt() -> Bool {
        if packageID == nil || version == nil {
            logger.log("\(self.name, privacy: .public): Unable to check installed package version. Missing 'packageid' or valid 'version'")
            return false
        }

        let task = Process()
        var plistOutput = ""
        var plist: pkgInfoPlist

        task.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        task.arguments = ["--pkg-info-plist", packageID!]
        if executeProcess(task: task, logger: logger, async: false, output: &plistOutput, printStderr: false) != 0 {
            logger.log("\(self.name, privacy: .public): Package receipt not found")
            return false
        }

        do {
            plist = try PropertyListDecoder().decode(pkgInfoPlist.self, from: plistOutput.data(using: .utf8)!)
        } catch {
            logger.error("\(self.name, privacy: .public) Unable to parse pkgutil output: \(String(describing: error), privacy: .public)")
            return false
        }
        if plist.pkgVersion >= version! {
            logger.info("\(self.name, privacy: .public): Installed version \(plist.pkgVersion, privacy: .public) is the same or newer than \(self.version!, privacy: .public)")
            return true
        }
        return false
    }

    func install() {
        if ias.options.dryRun {
            logger.log("\(self.name, privacy: .public): Dry run installing package \(self.filePath, privacy: .public)")
        } else {
            logger.log("\(self.name, privacy: .public): Installing package \(self.filePath, privacy: .public)")
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/installer")
            task.arguments = ["-verboseR", "-pkg", fileURL.path, "-target", "/"]
            returnCode = executeProcess(task: task, logger: logger, async: async)

            if returnCode != 0 {
                self.logger.warning("\(self.name, privacy: .public) Package install exited with non zero code \(self.returnCode, privacy: .public)")
            }
        }
    }

    override func execute() {
        guard executeCommon() else {
            return
        }

        logger.info("\(self.name, privacy: .public): Checking if package is already installed")
        if checkReceipt() {
            if packageRequired {
                logger.log("\(self.name, privacy: .public): Package is already installed but package is designated as required. Proceeding to install")
            } else {
                logger.log("\(self.name, privacy: .public): Package is already installed. Skipping")
                state = .finished
                return
            }
        }

        logger.info("\(self.name, privacy: .public): Proceeding to install")
        install()
        state = (returnCode == 0 ? .finished : .failed)
    }
}
