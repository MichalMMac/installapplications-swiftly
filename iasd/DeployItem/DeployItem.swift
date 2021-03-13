//
//  DeployItems.swift
//  installapplications-swiftly
//
//  2021 Michal Moravec
//

import Foundation
import os
import CryptoKit

enum ItemState {
    case initialized
    case downloading
    case downloaded
    case executing
    case finished
    case failed
    case failedDownload
}

class DeployItem: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate  {

    // Class shared part
    static let fileManager = FileManager()
    static let logger = Logger(subsystem: defaultDaemonIdentifier, category: "allitems")

    static var concurrencySemaphore = DispatchSemaphore(value: 1)
    static var concurrencyManipulationSemaphore = DispatchSemaphore(value: 1)
    static var concurrency = 1
    static var maximumDownloadConcurrency = 1

    // This should be done only when there are now dowloads in progress = in between phases
    static func resetDownloadConcurrency(value: Int) {
        DeployItem.logger.log("Reseting download concurrency to \(value)")
        DeployItem.concurrency = value
        DeployItem.concurrencySemaphore = DispatchSemaphore(value: value)
    }

    static func increaseDownloadConcurrency(increaseBy: Int) {
        concurrencyManipulationSemaphore.wait()
        for _ in 0..<increaseBy {
            if DeployItem.concurrency < DeployItem.maximumDownloadConcurrency {
                concurrencySemaphore.signal()
                DeployItem.concurrency += 1
                DeployItem.logger.log("Increased download concurrency to \(DeployItem.concurrency) (max: \(DeployItem.maximumDownloadConcurrency))")
            } else {
                break
            }
        }
        concurrencyManipulationSemaphore.signal()
    }

    // Single object part
    let async: Bool
    let failPolicy: ItemFailPolicy
    let fileURL: URL
    let filePath: String
    let name: String

    let downloadURL: URL?
    let expectedHash: String?
    let parallelGroup: String?

    let downloadSemphore = DispatchSemaphore(value: 0)

    private lazy var session = URLSession(configuration: .default, delegate: self,  delegateQueue: nil)

    var filePermissions: Int { 0o644 }
    var logger = Logger(subsystem: ias.options.identifier, category: "item")
    var reDownloadCounter = ias.options.redownloads
    var returnCode = 0
    var state = ItemState.initialized

    init(downloadURL: URL, fileURL: URL, name: String = "item", async: Bool = false, expectedHash: String? = nil) {
        self.downloadURL = downloadURL
        self.filePath = fileURL.path
        self.fileURL = fileURL
        self.name = name
        self.async = async
        self.expectedHash = expectedHash
        failPolicy = ItemFailPolicy.failureIsNotAnOption
        parallelGroup = nil
    }

    init(_ itemConfig: JsonItem) {
        if let urlString = itemConfig.url {
            downloadURL = URL(string: urlString)
        } else{
            downloadURL = nil
        }
        filePath = itemConfig.file
        fileURL = URL(fileURLWithPath: itemConfig.file)
        async = itemConfig.donotwait ?? false
        name = itemConfig.name
        expectedHash = itemConfig.hash
        failPolicy = itemConfig.failPolicy
        parallelGroup = itemConfig.parallelGroup
    }

    func removeFile() {
        try? DeployItem.fileManager.removeItem(at: fileURL)
    }

    func fileExists() -> Bool {
        if DeployItem.fileManager.fileExists(atPath: self.filePath) {
            return true
        }
        return false
    }

    func computeFileHash() -> SHA256.Digest? {
        do {
            let file = try FileHandle(forReadingFrom: self.fileURL)
            defer { try? file.close() }
            let bufferLength = 4096 * 1024
            var hash = SHA256.init()
            while let data = try file.read(upToCount: bufferLength) {
                hash.update(data: data)
            }
            return hash.finalize()
        } catch {
            logger.error("Error computing file \(self.filePath, privacy: .public) hash: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func compareFileWithExpectedHash(_ hash: String) -> Bool {
        if let fileHash = computeFileHash() {
            if fileHash.compactMap({ String(format: "%02x", $0) }).joined() == hash {
                logger.info("\(self.name, privacy: .public): Hash digest matches")
                return true
            }
        } else {
            logger.error("Unable to compare hash digests. Problem computing file \(self.filePath, privacy: .public) digest")
        }
        return false
    }

    func setFilePermission() {
        var attributes = [FileAttributeKey : Any]()
        attributes[.posixPermissions] = self.filePermissions
        do {
            try DeployItem.fileManager.setAttributes(attributes, ofItemAtPath: fileURL.path)
        } catch  {
            logger.error("Unable to set permission for file \(self.fileURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    func moveFile(downloadFile: URL) {
        self.removeFile()
        do {
            try DeployItem.fileManager.moveItem(at: downloadFile, to: fileURL)
        } catch {
            logger.error("file error: \(String(describing: error), privacy: .public)")
        }
    }

    func exitDownload() {
        DeployItem.concurrencySemaphore.signal()
        downloadSemphore.signal()
        DeployItem.increaseDownloadConcurrency(increaseBy: 1)
    }

    func failDownload() {
        self.logger.error("\(self.name, privacy: .public): Download failed")
        self.state = .failedDownload
        exitDownload()
    }

    func approveDownload() {
        self.logger.log("\(self.name, privacy: .public): Download successful")
        self.state = .downloaded
        exitDownload()
    }

    func reDownload() {
        if self.reDownloadCounter > 0 {
            self.reDownloadCounter -= 1
            logger.log("\(self.name, privacy: .public): Starting redownload")
            startDownload()
        }
        else {
            logger.error("\(self.name, privacy: .public): Reached maximum number of redownloads")
            self.failDownload()
        }
    }

    func checkDownload(failed: Bool = false) {
        if failed {
            reDownload()
        } else {
            switch ias.options.hashCheckPolicy {
            case .strict:
                if let hash = self.expectedHash {
                    if self.compareFileWithExpectedHash(hash) {
                        approveDownload()
                    } else {
                        logger.error("\(self.name, privacy: .public): (STRICT) Hash digest does not match")
                        reDownload()
                    }
                } else {
                    logger.error("\(self.name, privacy: .public): (STRICT) Unable to check SHA256 digest. Item has no hash key!")
                    failDownload()
                }
            case .warning:
                if let hash = self.expectedHash {
                    if self.compareFileWithExpectedHash(hash) {
                        approveDownload()
                    } else {
                        logger.log("\(self.name, privacy: .public): (WARNING) Hash digest does not match")
                        approveDownload()
                    }
                } else {
                    logger.log("\(self.name, privacy: .public): (WARNING) Unable to check SHA256 digest. Item has no hash key")
                    approveDownload()
                }
            case .ignore:
                approveDownload()
            }
        }
    }

    // URL Session download finished delegate
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        self.logger.debug("\(self.name, privacy: .public) Download attempt finished")

        if let response = downloadTask.response as? HTTPURLResponse {
            if !(200 ... 299 ~= response.statusCode) {
                self.logger.error("\(self.name, privacy: .public) dowload returned HTTP code \(response.statusCode, privacy: .public)")
                self.checkDownload(failed: true)
                return
            }
        }

        self.logger.debug("\(self.name, privacy: .public) Download attempt successful")
        self.moveFile(downloadFile: location)
        self.setFilePermission()
        self.checkDownload()
    }

    // URL Session download error delegate
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error != nil else {
            return
        }

        logger.error("\(self.name, privacy: .public): Download error \(String(describing: error), privacy: .public)")
        self.checkDownload(failed: true)
    }

    // URL Session download challange delegate
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        logger.debug("\(self.name, privacy: .public): Received authorization challange")

        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest:
            guard ias.options.httpAuthUser != nil && ias.options.httpAuthPassword != nil else {
                logger.error("\(self.name, privacy: .public): HTTP authentication required but credentials not configured")
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            if challenge.previousFailureCount == 0 {
                let credential = URLCredential(user: ias.options.httpAuthUser!, password: ias.options.httpAuthPassword!, persistence: .forSession)
                completionHandler(.useCredential, credential)
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func startDownload() {
        let downloadTask = session.downloadTask(with: downloadURL!)
        downloadTask.resume()
    }

    func downloadIfNeeded() {
        // Execution only items without URL
        if downloadURL == nil {
            logger.info("\(self.name, privacy: .public): Non-download item")
            if fileExists() {
                logger.info("\(self.name, privacy: .public): Non-download item exists")
                state = .downloaded
            } else {
                logger.error("\(self.name, privacy: .public): Non-download item missing")
                state = .failedDownload
            }
            downloadSemphore.signal()
            return
        }

        // Regular items with URL
        if fileExists() {
            logger.log("\(self.name, privacy: .public): Found existing file in place. Checking")
            checkDownload()
        } else {
            logger.log("\(self.name, privacy: .public): Starting download \(self.downloadURL!, privacy: .public)")
            // Wait if there is a maximum number of download in progress
            DeployItem.concurrencySemaphore.wait()
            self.state = .downloading
            startDownload()
        }
    }

    func execute() {
        _ = executeCommon()
    }

    func executeCommon() -> Bool {

        // Wait for download to finish
        downloadSemphore.wait()

        // Check if file id downloaded and ready for execution
        guard state == .downloaded else {
            return false
        }

        // Signal execution can proceed
        self.state = .executing
        return true
    }
}
