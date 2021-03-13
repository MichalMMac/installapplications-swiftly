//
//  DaemonXPC.swift
//  installapplications-swiftly
//
//  2021 Michal Moravec
//

import Foundation
import os

@objc class AgentXPCConnector: NSObject, IASDaemonXPCProtocol {

    let connectionEstablished = DispatchSemaphore(value: 0)
    let logger = Logger(subsystem: ias.options.identifier, category: "xpc")
    var connection: NSXPCConnection?
    var uid: Int?

    func agentCheckIn(agentEndpoint: NSXPCListenerEndpoint, agentUID: Int, withReply reply: @escaping (Bool) -> Void) {
        if connection == nil {
            connection = NSXPCConnection(listenerEndpoint: agentEndpoint)
            connection!.remoteObjectInterface = NSXPCInterface(with: IASAgentXPCProtocol.self)
            connection!.resume()
            uid = agentUID
            reply(true)
            logger.log("Agent UID:\(self.uid!, privacy: .public) checked in")
            connectionEstablished.signal()
        } else {
            logger.error("Received incoming connection but there is an agent alredy connected")
            reply(false)
        }
    }
}

class DaemonXPCServer : NSObject, NSXPCListenerDelegate {

    let agentConnector = AgentXPCConnector()
    let logger = Logger(subsystem: ias.options.identifier, category: "xpc")

    func waitForConnection() {
        let wakeInterval = 600
        var timeOutCounter = 0
        logger.log("Awaiting connection from agent")

        repeat {
            let timeOut = DispatchTime.now() + DispatchTimeInterval.seconds(wakeInterval)
            switch agentConnector.connectionEstablished.wait(timeout: timeOut) {
            case .success:
                logger.log("Connection established")
                return
            case .timedOut:
                logger.log("Still waiting for the agent connection")
            }
            timeOutCounter += wakeInterval
        } while timeOutCounter < ias.options.waitForAgentTimeout

        logger.error("Timed out while waiting for the agent connection")
        exit(1)
    }

    func runUserScript(scriptURL: URL, async: Bool) -> Int {
        var exitCode = 1
        let service = agentConnector.connection!.synchronousRemoteObjectProxyWithErrorHandler { error in
            self.logger.error("Problem with XPC connection: \(String(describing: error), privacy: .public)")
        } as? IASAgentXPCProtocol

        guard service != nil else {
            logger.error("Error using the protocol for the remote XPC Object")
            exit(1)
        }

        service!.executeUserScript(scriptURL: scriptURL, identifier: ias.options.identifier, async: async) { (reply) in
            exitCode = reply
            self.logger.debug("Finished Userscript XPC")
        }
        return exitCode
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: IASDaemonXPCProtocol.self)
        newConnection.exportedObject = agentConnector
        newConnection.resume()
        return true
    }
}
