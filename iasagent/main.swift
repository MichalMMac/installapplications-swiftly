//
//  main.swift
//  installapplications-swiftly
//
//  2021 Michal Moravec
//

import Foundation
import os

let logger = Logger(subsystem: DEFAULT_INTENFIER, category: "agent")

@objc class IAAgentXPC: NSObject, IAAgentXPCProtocol{

    func agentIsAlive(withReply reply: @escaping (Bool) -> Void) {
        reply(true)
    }

    func executeUserScript(scriptURL: URL, async: Bool, withReply reply: @escaping (Int) -> Void) {
    logger.log("Initiating user script \(scriptURL.path)")
    let task = Process()
    task.executableURL = scriptURL
    let returnCode = executeProcess(task: task, logger: logger, async: async)
    reply(returnCode)
  }
}

class ServiceDelegate : NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let exportedObject = IAAgentXPC()
        newConnection.exportedInterface = NSXPCInterface(with: IAAgentXPCProtocol.self)
        newConnection.exportedObject = exportedObject
        newConnection.resume()
        return true
    }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener(machServiceName: AGENT_SERVICE_INTENFIER)

logger.log("Agent has been launched by launchd")
listener.delegate = delegate;
listener.resume()
RunLoop.main.run()
