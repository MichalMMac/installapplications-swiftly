//
//  AgentXPC.swift
//  installapplications-swiftly
//
//  2021 Michal Moravec
//

import Foundation
import os

class AgentXPCConnection {
    let agentServiceIdentifier = AGENT_SERVICE_INTENFIER
    var agentConnection: NSXPCConnection?
    var agentConnectionEstablished = false
    let sleepTime = UInt32(WAIT_FOR_AGENT_SLEEPTIME)
    let logger = Logger(subsystem: ias.options.identifier, category: "xpcconnection")
    var scriptExitCode = 0

    func establishConnection() {
        var loopCounter = 0;
        while !agentConnectionEstablished {
            agentConnection = NSXPCConnection(machServiceName: agentServiceIdentifier)
            agentConnection!.remoteObjectInterface = NSXPCInterface(with: IAAgentXPCProtocol.self)
            agentConnection!.resume()
            let service = agentConnection!.synchronousRemoteObjectProxyWithErrorHandler { error in
            if loopCounter % 10 == 0 {
                self.logger.log("Agent not running yet")
                self.logger.debug("Agent could not connect: \(String(describing: error), privacy: .public)")
            }
            } as? IAAgentXPCProtocol
            service!.agentIsAlive() { (reply) in
                self.logger.log("Agent ready")
                self.agentConnectionEstablished = true
            }
            loopCounter += 1
            sleep(sleepTime)
        }
    }
    func runUserScript(scriptURL: URL, async: Bool) -> Int{
        let service = agentConnection!.synchronousRemoteObjectProxyWithErrorHandler { error in
            self.logger.error("Problem with XPC connection: \(String(describing: error), privacy: .public)")
        } as? IAAgentXPCProtocol
        service!.executeUserScript(scriptURL: scriptURL, async: async) { (reply) in
            self.scriptExitCode = reply
            self.logger.debug("Finished Userscript XPC")
        }
        return self.scriptExitCode
    }
}
