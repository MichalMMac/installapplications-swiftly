//
//  Reporter.swift
//  iasd
//
//  Created by michal on 23.04.2021.
//

import Foundation

protocol ReportModule {
    func setSteps(count: Int)
    func resetStep()
    func completeStep(message: String)
    func startStep(message: String)
    func report(message: String)
}

class Reporter {

    private let work = DispatchSemaphore(value: 0)

    enum Action {
        case beginStep
        case completeStep
        case report
        case resetStep
        case setStep
    }

    private var modules = [ReportModule]()
    private var queue = SharedQueue<(Any, Action)>()

    // Producer methods
    func beginStep(name: String) {
        queue.enqueue((name, .beginStep))
        work.signal()
    }

    func completeStep(name: String) {
        queue.enqueue((name, .completeStep))
        work.signal()
    }

    func setStep(count: Int){
        queue.enqueue((count, .setStep))
        work.signal()
    }

    func resetStep(){
        queue.enqueue((0, .resetStep))
        work.signal()
    }

    func report(name: String) {
        queue.enqueue((name, .report))
        work.signal()
    }

    // Consumer methods
    func add(module: ReportModule) {
        modules.append(module)
    }

    private func processItem() {
        if let item = self.queue.dequeue() {
            for module in self.modules {
                switch item.1 {
                case .beginStep:
                    module.startStep(message: item.0 as! String)
                case .completeStep:
                    module.completeStep(message: item.0 as! String)
                case .report:
                    module.report(message: item.0 as! String)
                case .setStep:
                    module.setSteps(count: item.0 as! Int)
                case .resetStep:
                    module.resetStep()
                }
            }
        }
    }

    func runAsync() {
        DispatchQueue.global().async {
            while true {
                self.work.wait()
                self.processItem()
            }
        }
    }
}
