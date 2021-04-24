//
//  Utils.swift
//  installapplications-swiftly
//
//  2021 Michal Moravec
//

import Foundation

// String version comparison extension from https://stackoverflow.com/questions/27932408/compare-two-version-strings-in-swift
extension String {

    // Modified from the DragonCherry extension - https://github.com/DragonCherry/VersionCompare
    private func compare(toVersion targetVersion: String) -> ComparisonResult {
        let versionDelimiter = "."
        var result: ComparisonResult = .orderedSame
        var versionComponents = components(separatedBy: versionDelimiter)
        var targetComponents = targetVersion.components(separatedBy: versionDelimiter)

        while versionComponents.count < targetComponents.count {
            versionComponents.append("0")
        }

        while targetComponents.count < versionComponents.count {
            targetComponents.append("0")
        }

        for (version, target) in zip(versionComponents, targetComponents) {
            result = version.compare(target, options: .numeric)
            if result != .orderedSame {
                break
            }
        }

        return result
    }

    func isVersion(equalTo targetVersion: String) -> Bool { return compare(toVersion: targetVersion) == .orderedSame }
    func isVersion(greaterThan targetVersion: String) -> Bool { return compare(toVersion: targetVersion) == .orderedDescending }
    func isVersion(greaterThanOrEqualTo targetVersion: String) -> Bool { return compare(toVersion: targetVersion) != .orderedAscending }
    func isVersion(lessThan targetVersion: String) -> Bool { return compare(toVersion: targetVersion) == .orderedAscending }
    func isVersion(lessThanOrEqualTo targetVersion: String) -> Bool { return compare(toVersion: targetVersion) != .orderedDescending }

    static func ==(lhs: String, rhs: String) -> Bool { lhs.compare(toVersion: rhs) == .orderedSame }
    static func <(lhs: String, rhs: String) -> Bool { lhs.compare(toVersion: rhs) == .orderedAscending }
    static func <=(lhs: String, rhs: String) -> Bool { lhs.compare(toVersion: rhs) != .orderedDescending }
    static func >(lhs: String, rhs: String) -> Bool { lhs.compare(toVersion: rhs) == .orderedDescending }
    static func >=(lhs: String, rhs: String) -> Bool { lhs.compare(toVersion: rhs) != .orderedAscending }

    // Appending to file from https://stackoverflow.com/questions/27327067/append-text-or-data-to-text-file-in-swift
    func appendLineToURL(fileURL: URL) throws {
        try (self + "\n").appendToURL(fileURL: fileURL)
    }

    func appendToURL(fileURL: URL) throws {
        let data = self.data(using: String.Encoding.utf8)!
        try data.append(fileURL: fileURL)
    }
}

extension Data {
    func append(fileURL: URL) throws {
        if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
        }
        else {
            try write(to: fileURL, options: .atomic)
        }
    }
}

struct SharedQueue<T> {
    private var array = [T]()
    private let access = DispatchSemaphore(value: 1)

    public var count: Int {
        access.wait()
        let count = array.count
        access.signal()
        return count
    }

    public var isEmpty: Bool {
        access.wait()
        let isEmpty = array.isEmpty
        access.signal()
        return isEmpty
    }

    public mutating func enqueue(_ element: T) {
        access.wait()
        array.append(element)
        access.signal()
    }

    public mutating func dequeue() -> T? {
        let item: T?
        access.wait()
        if array.isEmpty {
            item = nil
        } else {
            item = array.removeFirst()
        }
        access.signal()
        return item
    }

    public var front: T? {
        access.wait()
        let item = array.first
        access.signal()
        return item
    }
}
