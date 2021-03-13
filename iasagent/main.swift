//
//  main.swift
//  installapplications-swiftly
//
//  2021 Michal Moravec
//

import Foundation
import os

@objc class AgentXPCWorker: NSObject, IASAgentXPCProtocol {
    func executeUserScript(scriptURL: URL, identifier: String, async: Bool, withReply reply: @escaping (Int) -> Void) {
        let logger = Logger(subsystem: identifier, category: "agent")
        logger.log("Initiating user script \(scriptURL.path)")
        let task = Process()
        task.executableURL = scriptURL
        let returnCode = executeProcess(task: task, logger: logger, async: async)
        reply(returnCode)
    }
}

class AgentXPCServer : NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let exportedObject = AgentXPCWorker()
        newConnection.exportedInterface = NSXPCInterface(with: IASAgentXPCProtocol.self)
        newConnection.exportedObject = exportedObject
        newConnection.resume()
        return true
    }
}

let connectToDaemonTimeout = 300
let myUID = Int(getuid())
let logger = Logger(subsystem: defaultIdentifier, category: "agent")
logger.info("Agent startup")

// Prepare the anonymous listenter endpoint for the deamon to connect to
let anonymousDelegate = AgentXPCServer()
let anonymousListener = NSXPCListener.anonymous()
anonymousListener.delegate = anonymousDelegate
anonymousListener.resume()

logger.info("Trying to check in with the daemon")
var connectedToDaemon = false
var timeoutCounter = 0

while !connectedToDaemon {

    // Prepare the connection to the daemon
    let daemonConnection = NSXPCConnection(machServiceName: xpcServiceIdentifier, options: .privileged)
    daemonConnection.remoteObjectInterface = NSXPCInterface(with: IASDaemonXPCProtocol.self)
    daemonConnection.resume()

    let daemon = daemonConnection.synchronousRemoteObjectProxyWithErrorHandler { error in
        logger.log("Unable to connect to the daemon (yet)")
        logger.debug("\(String(describing: error), privacy: .public)")
        sleep(1)
    } as! IASDaemonXPCProtocol

    daemon.agentCheckIn(agentEndpoint: anonymousListener.endpoint, agentUID: myUID) { (reply) in
        guard reply else {
            logger.error("Daemon refused to accept the XPC endpoint")
            exit(1)
        }
        logger.info("Passed the XPC endpoint to the deamon")
        connectedToDaemon = true
    }
    timeoutCounter += 1
    guard timeoutCounter < connectToDaemonTimeout else {
        logger.error("Timed out while trying to connect to the daemon")
        exit(1)
    }
}

// Nothing more to do here. Only doing work for the daemon
logger.log("Agent is waiting for work from the daemon")
RunLoop.main.run()
