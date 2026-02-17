//
//  Logging.swift
//  NetMonitor
//
//  Centralized Logger definitions for structured logging.
//

import os

extension Logger {
    static let companion = Logger(subsystem: "com.netmonitor", category: "companion")
    static let discovery = Logger(subsystem: "com.netmonitor", category: "discovery")
    static let monitoring = Logger(subsystem: "com.netmonitor", category: "monitoring")
    static let data = Logger(subsystem: "com.netmonitor", category: "data")
    static let network = Logger(subsystem: "com.netmonitor", category: "network")
    static let app = Logger(subsystem: "com.netmonitor", category: "app")
}
