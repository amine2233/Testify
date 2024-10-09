//
//  RawTestResultParser.swift
//  Testify
//
//  Created by Tibor Bodecs on 2023. 02. 12..
//

import Foundation

private extension String {

    func match(_ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern)
        else { return nil }
        let matches = regex.matches(
            in: self,
            range: .init(location: 0, length: count)
        )
        guard let match = matches.first, 
                let range = Range(match.range, in: self)
        else { return nil }
        return String(self[range])
    }

    var matchedTestName: String? {
        guard let match = match("(\\'.+\\')") else {
            return nil
        }
        return String(match.dropFirst().dropLast())
    }
    
    var matchedDate: String? {
        match("(\\d{4}-\\d{2}-\\d{2}\\s\\d{2}\\:\\d{2}\\:\\d{2}\\.\\d{3})")
    }
    
    var matchedSeconds: String? {
        match("(\\d+\\.\\d+)")
    }
    
    var matchedUnexpected: String? {
        guard let dropFirst = match("\\((\\d+)")?.dropFirst() else { return nil }
        return String(dropFirst)
    }
}

public struct RawTestResultDecoder {
    
    private let dateFormatter: DateFormatter
    
    public init() {
        self.dateFormatter = .init()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }

    public func decode(_ input: String) throws -> TestSuite? {
        var suites: [TestSuite] = []
        var currentCaseName: String?
        var testCaseOutput: String = ""
        var gatherTestCaseOutput = false
        
        let lines = input.split(separator: "\n").map({ String($0) })
        for (index, line) in lines.enumerated() {
            // start or end test suite
            if line.contains("Test Suite") {
                if line.contains("started") {
                    guard let name = line.matchedTestName else { continue }
                    
                    guard let matchedDate = line.matchedDate,
                          let date =  dateFormatter.date(from: matchedDate)
                    else { continue }
                    
                    suites.append(
                        TestSuite(
                            name: name,
                            startDate: date,
                            endDate: date,
                            unexpected: 0,
                            outcome: .failure
                        )
                    )
                    continue;
                }
                else {
                    guard var suite = suites.last else { continue }
                    suites = Array(suites.dropLast())
                    
                    suite.outcome = line.contains("passed") ? .success : .failure
                    if let matchedDate = line.matchedDate,
                        let date =  dateFormatter.date(from: matchedDate) {
                        suite.endDate = date
                    }
                    if index+1 < lines.count {
                        let nextLine = lines[index+1]
                        if nextLine.contains("Executed"),
                           let matchedUnexpected = nextLine.matchedUnexpected,
                           let unexpected = UInt(matchedUnexpected) {
                            suite.unexpected = unexpected
                        }
                    }
                    
                    if suites.isEmpty {
                        suites.append(suite)
                    }
                    else {
                        if var parentSuite = suites.last {
                            suites = Array(suites.dropLast())
                            parentSuite.children.append(suite)
                            suites.append(parentSuite)
                        }
                    }
                    continue;
                }
            }
            if line.contains("Test Case") {
                if line.contains("started") {
                    testCaseOutput = ""
                    gatherTestCaseOutput = true
                    currentCaseName = line.matchedTestName
                    continue;
                }
                else {
                    gatherTestCaseOutput = false
                    guard var suite = suites.last else { continue }
                    suites = Array(suites.dropLast())
                    let outcome: Outcome = line.contains("passed") ? .success : .failure
                    
                    var failureInfo: FailureInfo? = nil
                    if outcome == .failure {
                        let outputSplit = testCaseOutput.split(separator: ":")
                        let file = String(outputSplit[0])
                        if let line = Int(outputSplit[1]) {
                            let reason = String(outputSplit.dropFirst(4)
                                .joined(separator: ":")
                                .trimmingCharacters(in: CharacterSet(charactersIn: "-").union(.whitespaces)))
                            failureInfo = FailureInfo(file: file, line: line, reason: reason)
                        }
                    }
                    
                    if let _currentCaseName = currentCaseName,
                        let matchedSeconds = line.matchedSeconds,
                        let duration = TimeInterval(matchedSeconds) {
                        
                        let caseName = _currentCaseName.dropFirst(2).dropLast()
                        let firstSplit = caseName.split(separator: ".")
                        let secondSplit = firstSplit[1].split(separator: " ")
                        let testCase = TestCase(
                            moduleName: String(firstSplit[0]),
                            className: String(secondSplit[0]),
                            testName: String(secondSplit[1]),
                            duration: duration,
                            outcome: outcome,
                            failureInfo: failureInfo
                        )
                        suite.cases.append(testCase)
                        suites.append(suite)
                        currentCaseName = nil
                    }
                    continue;
                }
            }
            if gatherTestCaseOutput {
                testCaseOutput += line
            }
        }
        return suites.first
    }
}
