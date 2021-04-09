//
//  main.swift
//  installapplications-swiftly
//
//  2021 Michal Moravec
//

import Foundation
import os

class InstallApplicationSwiftly {

    let fileManager: FileManager
    let launchAgentPlist: URL
    let launchDaemonPlist: URL
    let logger: Logger

    var xpcServer: DaemonXPCServer?
    var xpcListner: NSXPCListener?

    init() {
        // Set variables
        logger = Logger(subsystem: settings.identifier, category: "main")
        fileManager = FileManager()
        launchDaemonPlist = URL(fileURLWithPath: "/Library/LaunchDaemons").appendingPathComponent(settings.launchDaemonIdentifier).appendingPathExtension("plist")
        launchAgentPlist = URL(fileURLWithPath: "/Library/LaunchAgents").appendingPathComponent(settings.launchAgentIdentifier).appendingPathExtension("plist")
    }

    func startXPCListener() {
        xpcServer = DaemonXPCServer()
        xpcListner = NSXPCListener(machServiceName: xpcServiceIdentifier)

        xpcListner!.delegate = xpcServer;
        xpcListner!.resume()
    }

    func checkRoot() {
        let user = NSUserName()
        if user != "root" && !settings.dryRun {
            logger.error("iasd must be run as root user! Current user: \(user, privacy: .public)")
            exit(1)
        }
    }

    func createDirectories() {
        logger.info("InstallApplications-Swiftly path: \(settings.iasPath, privacy: .public)")
        do {
            try fileManager.createDirectory(at: settings.iasPath, withIntermediateDirectories: true, attributes: [FileAttributeKey.posixPermissions: 0o755])
            // Crate IAS userscripts directory for backward compatibility
            try fileManager.createDirectory(at: settings.iasPath.appendingPathComponent("userscripts"), withIntermediateDirectories: true, attributes: [FileAttributeKey.posixPermissions: 0o755])
        } catch {
            logger.error("Unable to crate directories: \(String(describing: error), privacy: .public)")
        }
    }

    func beginRun() {

        // Crate necessary directories
        self.createDirectories()

        logger.log("Beginning InstallApplications-Swiftly run")

        // Prepare conrol JSON URLs
        let jsonFileURL =  settings.iasPath.appendingPathComponent(settings.jsonURL!.lastPathComponent)

        // Download and parse control JSON
        logger.info("JSON path: \(jsonFileURL.path, privacy: .public)")
        let control = JSONControlItem(downloadURL: settings.jsonURL!, fileURL: jsonFileURL, name: "JSON control")
        if !settings.skipJSONValidation && control.fileExists() {
            logger.log("Removing the existing JSON control file")
            control.removeFile()
        }

        control.downloadIfNeeded()
        control.execute() // Wait for download to complete

        let controlData = control.parse()

        // Set download concurrency for Preflight phase
        DeployItem.maximumDownloadConcurrency = settings.maxDownloadConcurrency
        DeployItem.resetDownloadConcurrency(value: settings.minDownloadConcurrency)

        // Run preflight phase
        let prelightPhase = Preflight(itemList: controlData.preflight)
        prelightPhase.downloadResources()
        prelightPhase.begin()
        if let check = prelightPhase.check {
            if check {
                logger.log("Preflight passed all checks. Skipping run.")
                quit(exitCode: 0)
            } else {
                logger.log("Preflight did not pass all checks. Continuing run.")
            }
        }

        // Reset download concurrency for SetupAssistant and Userland phases
        DeployItem.resetDownloadConcurrency(value: settings.minDownloadConcurrency)

        let setupAssistantPhase = SetupAssistant(itemList: controlData.setupassistant)
        let userlandPhase = Userland(itemList: controlData.userland)

        // Start dowloding data for SetupAssistant and Userland phases asynchronously
        DispatchQueue.global().async {
            setupAssistantPhase.downloadResources()
            userlandPhase.downloadResources()
        }

        // Run SetupAssistant phase
        setupAssistantPhase.begin()

        // Run Userland phase
        userlandPhase.begin()
    }

    func finish() {
        logger.log("Cleaning UP")

        logger.info("Attempting to remove LaunchDaemon \(self.launchDaemonPlist.path, privacy: .public)")
        try? fileManager.removeItem(at: self.launchDaemonPlist)

        logger.info("Attempting to remove LaunchAgent \(self.launchAgentPlist.path, privacy: .public)")
        try? fileManager.removeItem(at: self.launchAgentPlist)

        // Unload LaunchAgent
        if xpcServer!.agentConnector.connection != nil && xpcServer!.agentConnector.uid != nil {
            logger.info("Attempting to unload LaunchAgent \(settings.launchAgentIdentifier, privacy: .public)")
            let agentUnload = Process()
            agentUnload.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            agentUnload.arguments = ["bootout", "gui/\(String(xpcServer!.agentConnector.uid!))/\(settings.launchAgentIdentifier)"]
            _ = executeProcess(task: agentUnload, logger: logger, async: false)
        }

        // Clean UP IAS directory
        try? fileManager.removeItem(at: settings.iasPath)

        // Trigger delayed reboot
        if settings.reboot {
            logger.log("Triggering reboot")
            let delayedReboot = Process()
            delayedReboot.executableURL = URL(fileURLWithPath: "/bin/zsh")
            delayedReboot.arguments = ["-c", "sleep 5; /bin/launchctl reboot system"]
            _ = executeProcess(task: delayedReboot, logger: logger, async: true)
        }

        // Unload LaunchDaemon
        logger.info("Attempting to unload LaunchDaemon \(settings.launchDaemonIdentifier, privacy: .public)")
        let daemonUnload = Process()
        daemonUnload.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        daemonUnload.arguments = ["bootout", "system/\(settings.launchDaemonIdentifier)"]
        _ = executeProcess(task: daemonUnload, logger: logger, async: true)
    }

    func quit(exitCode: Int) {
        finish()
        logger.log("Exiting with code: \(exitCode, privacy: .public)")
        exit(Int32(exitCode))
    }
}

let settings = Settings()
settings.check()

let ias = InstallApplicationSwiftly()
ias.checkRoot()
ias.startXPCListener()
ias.beginRun()

/*
 If the last task is a donotwait script there is a race condition when finish() deletes the file before task.run()
 loads the script from file and starts executing.
 */
sleep(5)

// Clean up and exit successfully
ias.quit(exitCode: 0)
