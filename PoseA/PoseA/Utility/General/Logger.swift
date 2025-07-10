//  *** IMPORTANT ***
//  Logger.swift
//  PoseA
//
//  Created by Ardhika Maulidani on 6/9/25.
//  Custom Logger Function

import Foundation
import os

enum LogLevel {
    case debug, info, warn, error
}

func log(_ message: String, level: LogLevel = .debug, file: String = #file, function: String = #function) {
    let fileName = (file as NSString).lastPathComponent
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "App", category: fileName)

    switch level {
    case .debug:
        logger.debug("\(fileName) - \(function): \(message)")
    case .info:
        logger.info("\(fileName) - \(function): \(message)")
    case .warn:
        logger.warning("\(fileName) - \(function): \(message)")
    case .error:
        logger.error("\(fileName) - \(function): \(message)")
    }
}
