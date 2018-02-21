//  PapertrailLumberjack
//
//  Created by Chad Robinson on 2/20/2018.
//  Copyright (c) 2018 Media Lantern, Inc. All rights reserved.

import Foundation
import CocoaLumberjack
import CocoaAsyncSocket

class PapertrailLumberjack: DDAbstractLogger, GCDAsyncSocketDelegate, GCDAsyncUdpSocketDelegate {
    var tcpSocket: GCDAsyncSocket?
    var udpSocket: GCDAsyncUdpSocket?

    var host: String?
    var port: UInt16 = 0
    var tcp = false
    var udp = false
    var tls = true
    var debug = false

    var dateFormatter: DateFormatter
    var machineName: String = ""
    var programName: String = ""

    override init() {
        dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        machineName = UIDevice.current.identifierForVendor?.uuidString ?? ""

        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as! String
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
        programName = "\(appName)-\(version)-\(build)"
    }

    func disconnect() {
        tcpSocket?.disconnect()
        tcpSocket = nil

        udpSocket?.close()
        udpSocket = nil
    }

    @objc(logMessage:)
    override func log(message logMessage: DDLogMessage) {
        guard port != 0 else { return }
        guard let host = host else { return }

        let msg = formatMessage(logMessage)

        if (tcp) {
            checkTcpSocket()
            tcpSocket?.write(msg.data(using: .utf8)!, withTimeout: -1, tag: 1)
        } else {
            checkUdpSocket()
            udpSocket?.send(msg.data(using: .utf8)!, toHost: host, port: port, withTimeout: -1, tag: 1)
        }
    }

    func checkTcpSocket() {
        guard tcpSocket == nil else { return }

        guard port != 0 else { return }
        guard let host = host else { return }

        tcpSocket = GCDAsyncSocket(delegate: self, delegateQueue: DispatchQueue.main)

        if (debug) {
            print("[PapertrailLumberjack] Connecting to Papertrail (\(host):\(port))")
        }

        do {
            try tcpSocket?.connect(toHost: host, onPort: port)
        } catch let e {
            print("[PapertrailLumberjack] Error connecting Papertrail (\(e.localizedDescription))")
        }

        if (tls) {
            if (debug) {
                print("[PapertrailLumberjack] Starting TLS")
            }

            tcpSocket?.startTLS(nil)
        }
    }

    func checkUdpSocket() {
        guard udpSocket == nil else { return }

        udpSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: DispatchQueue.main)
    }

    func formatMessage(_ logMessage: DDLogMessage) -> String {
        let msg = logMessage.message.trimmingCharacters(in: .newlines)
        var logLevel = "15"

        switch (logMessage.flag) {
        case .error:
            logLevel = "11"
        case .warning:
            logLevel = "12"
        case .info:
            logLevel = "14"
        default:
            logLevel = "15"
        }

        // Thanks, Apple... That reorg totally made sense...
        let file = URL(fileURLWithPath: logMessage.file).lastPathComponent

        // Syslog format...
        let timestamp = dateFormatter.string(from: logMessage.timestamp)
        return "<\(logLevel)>\(timestamp) \(machineName) \(programName): \u{001B}[0;36m\(file):\(logMessage.line)\u{001B}[0m \u{001B}[0;35m\(logMessage.function ?? "-")\u{001B}[0m \(msg)\n"
    }
}
