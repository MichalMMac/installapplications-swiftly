//
//  SetupAssistant.swift
//  installapplications-swiftly
//
//  2021 Michal Moravec
//

import Foundation
import os

class SetupAssistant: Phase {

    init(itemList: [JsonItem]?) {
        super.init()
        logger =  Logger(subsystem: settings.identifier, category: "setupassistant")

        for item in itemList ?? [] {
            switch item.type {
            case .package:
                self.items.append(Package(item))
            case .rootScript:
                self.items.append(RootScript(item))
            case .userScript, .unknown:
                logger.error("Invalid item type: \(item.type.rawValue, privacy: .public) present in SetupAssistant phase. Ignoring")
            }
        }
    }

    func begin() {
        logger.log("Beginning SetupAssistant phase")
        if items.isEmpty{
            logger.log("No SetupAssistant items found. Skipping")
            return
        }
        runItems()
    }
}

