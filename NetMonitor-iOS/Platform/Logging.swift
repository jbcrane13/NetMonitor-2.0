import os

extension Logger {
    // periphery:ignore
    static let companion = Logger(subsystem: "com.blakemiller.netmonitor", category: "companion")
    // periphery:ignore
    static let discovery = Logger(subsystem: "com.blakemiller.netmonitor", category: "discovery")
    // periphery:ignore
    static let monitoring = Logger(subsystem: "com.blakemiller.netmonitor", category: "monitoring")
    // periphery:ignore
    static let data = Logger(subsystem: "com.blakemiller.netmonitor", category: "data")
    // periphery:ignore
    static let network = Logger(subsystem: "com.blakemiller.netmonitor", category: "network")
    // periphery:ignore
    static let app = Logger(subsystem: "com.blakemiller.netmonitor", category: "app")
    // periphery:ignore
    static let background = Logger(subsystem: "com.blakemiller.netmonitor", category: "background")
    // periphery:ignore
    static let geofence = Logger(subsystem: "com.blakemiller.netmonitor", category: "geofence")
}
