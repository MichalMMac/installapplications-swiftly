//
//  iaclasses.swift
//  installapplications-swiftly
//
//  2021 Michal Moravec
//

import Foundation
import os

class Phase {

    let dispatchGroup = DispatchGroup()
    var logger: Logger
    var items: [DeployItem] = []

    init() {
        logger = Logger(subsystem: settings.identifier, category: "phase")
    }

    func proceedAfterExecution(name: String, state: ItemState, policy: ItemFailPolicy) -> Bool {
        // Handle failed download state
        if state == .failedDownload {
            if policy == .failable {
                self.logger.log("\(name, privacy: .public) is in the failed state after the download but is failable. Proceeding")
                return true
            } else {
                self.logger.error("\(name, privacy: .public) is in the failed state after the download. Exiting")
                return false
            }
        }

        // Handle failed execution state
        if state == .failed {
            if policy == .failureIsNotAnOption {
                self.logger.error("\(name, privacy: .public) is in the illegal failed state after the execution. Exiting")
                return false
            } else {
                self.logger.info("\(name, privacy: .public) is in the failed state after the execution but failure is tolerated. Proceeding")
                return true
            }
        }

        // state is OK
        return true
    }

    func downloadResources() {
        for item in items {
            item.downloadIfNeeded()
        }
    }

    func runItems() {
        var runningParallelGroup: String?
        var exitSignal = false

        executionLoop: for item in items {
            if runningParallelGroup != nil {
                if item.parallelGroup != runningParallelGroup! {
                    // Wait for previous parallel group to finish
                    dispatchGroup.wait()
                    runningParallelGroup = nil
                    // Parallel group item(s) with failureIsNotAnOption failed -> Break after whole group is done
                    if exitSignal {
                        break executionLoop
                    }
                }
            }

            if let parallelGroup = item.parallelGroup {
                dispatchGroup.enter()
                runningParallelGroup = parallelGroup
                logger.log("\(item.name, privacy: .public): Starting parallel run (group: \(parallelGroup, privacy: .public)")
                DispatchQueue.global().async {
                    item.execute()
                    if !self.proceedAfterExecution(name: item.name, state: item.state, policy: item.failPolicy) {
                        exitSignal = true
                    }
                   self.dispatchGroup.leave()
               }
            } else {
                logger.log("\(item.name, privacy: .public): Starting \(item.async ? "asynchronous" : "synchronous", privacy: .public) run")
                item.execute()
                if !proceedAfterExecution(name: item.name, state: item.state, policy: item.failPolicy) {
                    exitSignal = true
                    break executionLoop
                }
            }
        }

        if runningParallelGroup != nil {
           dispatchGroup.wait()
           runningParallelGroup = nil
        }

        if exitSignal {
            ias.quit(exitCode: 1)
        }
    }
}
