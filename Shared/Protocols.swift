//
//  Protocols.swift
//  installapplications-swiftly
//
//  2021 Michal Moravec
//

import Foundation

@objc(IAAgentXPCProtocol) protocol IAAgentXPCProtocol {
  func executeUserScript(scriptURL: URL, async: Bool, withReply reply: @escaping (Int) -> Void)
  func agentIsAlive(withReply reply: @escaping (Bool) -> Void)
}
