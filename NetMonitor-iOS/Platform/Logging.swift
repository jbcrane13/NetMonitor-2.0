import os

extension Logger {
    static let companion = Logger(subsystem: "com.blakemiller.netmonitor", category: "companion")
    static let discovery = Logger(subsystem: "com.blakemiller.netmonitor", category: "discovery")
    static let monitoring = Logger(subsystem: "com.blakemiller.netmonitor", category: "monitoring")
    static let data = Logger(subsystem: "com.blakemiller.netmonitor", category: "data")
    static let network = Logger(subsystem: "com.blakemiller.netmonitor", category: "network")
    static let app = Logger(subsystem: "com.blakemiller.netmonitor", category: "app")
    static let background = Logger(subsystem: "com.blakemiller.netmonitor", category: "background")
    static let geofence = Logger(subsystem: "com.blakemiller.netmonitor", category: "geofence")
}
