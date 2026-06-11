import os

/// Shared logger for the capture path. Read the live capture diagnostics with:
///   log show --last 5m --predicate 'subsystem == "com.in-venture.in-meetings"' --style compact
let captureLog = Logger(subsystem: "com.in-venture.in-meetings", category: "capture")
