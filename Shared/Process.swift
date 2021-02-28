//
//  Process.swift
//  installapplications-swiftly
//
//  2021 Michal Moravec
//

import Foundation
import os

func executeProcess(task: Process, logger: Logger, async: Bool) -> Int {
    var output = ""
    return executeProcess(task: task, logger: logger, async: async, output: &output, printStdout: true)
}

func executeProcess(task: Process, logger: Logger, async: Bool, output: inout String, printStdout: Bool = false) -> Int {
    let stdout = Pipe()
    let stderr = Pipe()
    task.standardOutput = stdout
    task.standardError = stderr
    do {
        try task.run()
        logger.debug("Script running")
    } catch {
        logger.error("Failure running task \(task.arguments!, privacy: .public)")
        logger.error("\(String(describing: error), privacy: .public)")
        // Spíše return?
        //exit(1)
    }
    if !async {
        logger.debug("Waiting for script to finish")
        task.waitUntilExit()
        //TODO lepší handling outputu možná v samostatném threadu?
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
        output = out
        let errout = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
        if !out.isEmpty && printStdout {
            logger.log("Output on stdout: \(out, privacy: .public)")
        }
        if !errout.isEmpty {
            logger.error("Output on stderr: \(errout, privacy: .public)")
        }
        return Int(task.terminationStatus)
    }
    return 0
}
