//
//  Userland.swift
//  installapplications-swiftly
//
//  2021 Michal Moravec
//

import Foundation
import os

class Userland: Phase {

    init(itemList: [JsonItem]?) {
        super.init()
        logger = Logger(subsystem: ias.options.identifier, category: "userland")

        for item in itemList ?? [] {
            switch item.type {
            case .package:
                self.items.append(Package(item))
            case .rootScript:
                self.items.append(RootScript(item))
            case .userScript:
                self.items.append(UserScript(item))
            case .unknown:
                logger.error("Invalid item type: \(item.type.rawValue, privacy: .public) present in Userland phase. Ignoring")
            }
        }
    }

    func begin() {
        logger.log("Beginning Userland phase")
        if items.isEmpty{
            logger.log("No Userland items found. Skipping")
            return
        }
        let agent = AgentXPCConnection()
        agent.establishConnection()
        runItems()
    }
}
