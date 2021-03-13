//
//  Protocols.swift
//  installapplications-swiftly
//
//  2021 Michal Moravec
//

import Foundation

@objc(IASDaemonXPCProtocol) protocol IASDaemonXPCProtocol {
    func agentCheckIn(agentEndpoint: NSXPCListenerEndpoint, agentUID: Int, withReply reply: @escaping (Bool) -> Void)
}

@objc(IASAgentXPCProtocol) protocol IASAgentXPCProtocol {
  func executeUserScript(scriptURL: URL, identifier: String, async: Bool, withReply reply: @escaping (Int) -> Void)
}
