//
//  Preflight.swift
//  installapplications-swiftly
//
//  2021 Michal Moravec
//

import Foundation
import os

class Preflight: Phase {

    private let checkSemaphore = DispatchSemaphore(value: 1)
    private var _check: Bool?

    var check: Bool? {
        get {
            checkSemaphore.wait()
            let returnCheck = _check
            checkSemaphore.signal()
            return returnCheck
        }
        set {
            checkSemaphore.wait()
            // Once any prelifht check script does not pass entire preflight shall not pass
            if self._check != false {
               self._check = newValue
            }
            checkSemaphore.signal()
        }
    }

    init(itemList: [JsonItem]?) {
        super.init()
        logger = Logger(subsystem: settings.identifier, category: "preflight")

        for item in itemList ?? [] {
            switch item.type {
            case .rootScript:
                self.items.append(RootScript(item))
            case .package, .userScript, .unknown:
                logger.error("Invalid item type: \(item.type.rawValue, privacy: .public) present in Preflight phase. Ignoring")
            }
        }
    }

    func begin() {
        self.logger.log("Beginning Preflight phase")

        if items.isEmpty{
            logger.log("No Preflight items found. Skipping")
            return
        }

        var exitSignal = false
        for item in items {
            self.dispatchGroup.enter()
            DispatchQueue.global().async {
                item.execute()
                ias.reporter.completeStep(name: "Finished: \(item.name)")
                if !self.proceedAfterExecution(name: item.name, state: item.state, policy: item.failPolicy) {
                    exitSignal = true
                }
                if item.returnCode == 0 {
                    self.check = true
                } else {
                    self.check = false
                }
                self.dispatchGroup.leave()
            }
            self.dispatchGroup.wait()
            if exitSignal {
                ias.quit(exitCode: 1)
            }
        }
    }
}
