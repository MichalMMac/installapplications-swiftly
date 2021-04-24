//
//  DEPNotify.swift
//  iasd
//
//  Created by michal on 23.04.2021.
//

import Foundation
import os

class DEPNotify : ReportModule {

    let controlFile: URL
    var numberOfSteps: Int?
    let logger: Logger
    var currentStep = 0
    var failed = false

    init() {

        controlFile = settings.DEPNotifyControlFile
        logger = Logger(subsystem: settings.identifier, category: "DEPNotify")

        if !FileManager.default.fileExists(atPath: controlFile.path) {
            do {
                try "".write(to: controlFile, atomically: false, encoding: .utf8)
            } catch {
                failed = true
                self.logger.error("Unable to create DEPNotify control file")
            }
        }
    }

    func appendToControlFile(command: String) {
        do {
            self.logger.debug("Writing to control file")
            try command.appendLineToURL(fileURL: controlFile)
        } catch {
            failed = true
            self.logger.error("Unable to write to DEPNotify control file")
        }
    }
    
    func completeStep(message: String) {
        currentStep += 1
        guard !failed && numberOfSteps != nil else {
            return
        }
        if settings.DEPNotifyDeterminate {
            self.logger.debug("Moving the step")
            appendToControlFile(command: "Command: DeterminateManualStep: 1")
            if currentStep == numberOfSteps! {
                resetStep() 
            }
        }
    }

    func resetStep() {
        guard !failed && numberOfSteps != nil else {
            return
        }
        if settings.DEPNotifyDeterminate {
            appendToControlFile(command: "Command: DeterminateOffReset")
        }
    }

    func setSteps(count: Int) {
        self.logger.debug("Setting steps to: \(count)")
        numberOfSteps = count
        if settings.DEPNotifyDeterminate {
            appendToControlFile(command: "Command: DeterminateManual: \(numberOfSteps!)")
        }
    }

    func startStep(message: String) {
        guard !failed else {
            return
        }
        self.logger.debug("Adding message")
        appendToControlFile(command: "Status: \(message)")
    }

    func report(message: String) {
        startStep(message: message)
    }
}
