//
//  main.swift
//  installapplications-swiftly
//
//  2021 Michal Moravec
//

import Foundation
import os

class InstallApplicationSwiftly {

    let configFile: URL
    let fileManager: FileManager
    let launchAgentPlist: URL
    let launchDaemonPlist: URL
    let logger: Logger
    let options: Options

    var xpcServer: DaemonXPCServer?
    var xpcListner: NSXPCListener?

    init() {
        // Load settings
        let arguments = CommandLine.arguments
        if arguments.count > 1 {
            configFile = URL(fileURLWithPath: arguments[1])
        } else {
            configFile = URL(fileURLWithPath: arguments[0]).deletingLastPathComponent().appendingPathComponent(daemonConfigFileName)
        }
        options = loadOptions(fromFile: configFile)

        // Set variables
        logger = Logger(subsystem: options.identifier, category: "main")
        fileManager = FileManager()
        launchDaemonPlist = URL(fileURLWithPath: "/Library/LaunchDaemons").appendingPathComponent(options.launchDaemonIdentifier).appendingPathExtension("plist")
        launchAgentPlist = URL(fileURLWithPath: "/Library/LaunchAgents").appendingPathComponent(options.launchAgentIdentifier).appendingPathExtension("plist")
    }

    func startXPCListener() {
        xpcServer = DaemonXPCServer()
        xpcListner = NSXPCListener(machServiceName: xpcServiceIdentifier)

        xpcListner!.delegate = xpcServer;
        xpcListner!.resume()
    }

    func checkRoot() {
        let user = NSUserName()
        if user != "root" && !options.dryRun {
            logger.error("iasd must be run as root user! Current user: \(user, privacy: .public)")
            exit(1)
        }
    }

    func createDirectories() {
        logger.info("InstallApplications-Swiftly path: \(self.options.iasPath, privacy: .public)")
        let iasDirectoryURL = URL(fileURLWithPath: options.iasPath)
        do {
            try fileManager.createDirectory(at: iasDirectoryURL, withIntermediateDirectories: true, attributes: [FileAttributeKey.posixPermissions: 0o755])
            // Crate IAS userscripts directory for backward compatibility
            try fileManager.createDirectory(at: iasDirectoryURL.appendingPathComponent("userscripts"), withIntermediateDirectories: true, attributes: [FileAttributeKey.posixPermissions: 0o755])
        } catch {
            logger.error("Unable to crate directories: \(String(describing: error), privacy: .public)")
        }
    }

    func beginRun() {

        // Crate necessary directories
        self.createDirectories()

        logger.log("Beginning InstallApplications-Swiftly run")

        // Prepare conrol JSON URLs
        let jsonDownloadURL = URL(string: options.jsonURL)!
        let jsonFileURL = URL(fileURLWithPath: options.iasPath).appendingPathComponent(jsonDownloadURL.lastPathComponent)

        // Download and parse control JSON
        logger.info("JSON path: \(jsonFileURL.path, privacy: .public)")
        let control = JSONControlItem(downloadURL: jsonDownloadURL, fileURL: jsonFileURL, name: "JSON control")
        if !options.skipJSONValidation && control.fileExists() {
            logger.log("Removing the existing JSON control file")
            control.removeFile()
        }

        control.downloadIfNeeded()
        control.execute() // Wait for download to complete

        let controlData = control.parse()

        // Set download concurrency for Preflight phase
        DeployItem.maximumDownloadConcurrency = options.maxDownloadConcurrency
        DeployItem.resetDownloadConcurrency(value: options.minDownloadConcurrency)

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
        DeployItem.resetDownloadConcurrency(value: options.minDownloadConcurrency)

        let setupAssistantPhase = SetupAssistant(itemList: controlData.setupassistant)
        let userlandPhase = Userland(itemList: controlData.userland)

        // Start dowloding data for SetupAssistant and Userland phases asynchronously
        setupAssistantPhase.downloadResources()
        userlandPhase.downloadResources()

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
            logger.info("Attempting to unload LaunchAgent \(self.options.launchAgentIdentifier, privacy: .public)")
            let agentUnload = Process()
            agentUnload.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            agentUnload.arguments = ["bootout", "gui/\(String(xpcServer!.agentConnector.uid!))/\(self.options.launchAgentIdentifier)"]
            _ = executeProcess(task: agentUnload, logger: logger, async: false)
        }

        // Clean UP IAS directory
        try? fileManager.removeItem(atPath: options.iasPath)

        // Trigger delayed reboot
        if options.reboot {
            logger.log("Triggering reboot")
            let delayedReboot = Process()
            delayedReboot.executableURL = URL(fileURLWithPath: "/bin/zsh")
            delayedReboot.arguments = ["-c", "sleep 5; /bin/launchctl reboot system"]
            _ = executeProcess(task: delayedReboot, logger: logger, async: true)
        }

        // Unload LaunchDaemon
        logger.info("Attempting to unload LaunchDaemon \(self.options.launchDaemonIdentifier, privacy: .public)")
        let daemonUnload = Process()
        daemonUnload.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        daemonUnload.arguments = ["bootout", "system/\(self.options.launchDaemonIdentifier)"]
        _ = executeProcess(task: daemonUnload, logger: logger, async: true)
    }

    func quit(exitCode: Int) {
        finish()
        logger.log("Exiting with code: \(exitCode, privacy: .public)")
        exit(Int32(exitCode))
    }
}

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
