import SwiftUI
import Cocoa
import os

@main
struct KeystrokeCounterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger()
    var statusItem: NSStatusItem?
    var eventMonitor: Any?
    var totalKeyCount: Int = UserDefaults.standard.integer(forKey: "totalKeyCount")
    var dailyKeyCount: Int = 0
    var isShowingTotal: Bool = UserDefaults.standard.bool(forKey: "isShowingTotal")
    let calendar = Calendar.current
    var popover: NSPopover?
    
    @Published var currentYear: Int = Calendar.current.component(.year, from: Date())
    @Published var isHistoryViewOpen: Bool = false
    
    // Add this for test mode
    let testMode = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSavedCounts()
        checkAndResetDailyCount()
        setupStatusItem()
        requestAccessibilityPermission()
        setupPopover()
    }
    
    func loadSavedCounts() {
        totalKeyCount = UserDefaults.standard.integer(forKey: "totalKeyCount")
        dailyKeyCount = 0
        isShowingTotal = UserDefaults.standard.bool(forKey: "isShowingTotal")
    }
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemTitle()
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle History", action: #selector(toggleHistory), keyEquivalent: "h"))
        menu.addItem(NSMenuItem(title: isShowingTotal ? "Show Today" : "Show All Time", action: #selector(toggleCountDisplay), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.shared.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if accessEnabled {
            setupEventMonitor()
        }
    }
    
    func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyUp]) { [weak self] _ in
            self?.incrementCount()
        }
    }
    
    func incrementCount() {
        totalKeyCount += 1
        dailyKeyCount += 1
        UserDefaults.standard.set(totalKeyCount, forKey: "totalKeyCount")
        UserDefaults.standard.set(dailyKeyCount, forKey: "dailyKeyCount")
        updateStatusItemTitle()
    }
    
    func updateStatusItemTitle() {
        DispatchQueue.main.async {
            if self.isHistoryViewOpen {
                self.statusItem?.button?.title = String(self.currentYear)
            } else {
                let count = self.isShowingTotal ? self.totalKeyCount : self.dailyKeyCount
                self.statusItem?.button?.title = self.formatCount(count)
            }
        }
    }
    
    func formatCount(_ count: Int) -> String {
        let wrappedCount = count % 1_000_000_000_000 // Wrap at 1T
        switch wrappedCount {
        case 0..<1000: return "\(wrappedCount)"
        case 1000..<1_000_000: return String(format: "%.1fk", Double(wrappedCount) / 1000.0)
        case 1_000_000..<1_000_000_000: return String(format: "%.1fM", Double(wrappedCount) / 1_000_000.0)
        default: return String(format: "%.1fB", Double(wrappedCount) / 1_000_000_000.0)
        }
    }
    
    @objc func toggleCountDisplay() {
        isShowingTotal.toggle()
        UserDefaults.standard.set(isShowingTotal, forKey: "isShowingTotal")
        updateStatusItemTitle()
        setupStatusItem()
    }
    
    func checkAndResetDailyCount() {
        let lastResetDate = UserDefaults.standard.object(forKey: "lastResetDate") as? Date ?? Date.distantPast
        let now = Date()
        
        if calendar.isDate(lastResetDate, inSameDayAs: now) {
            // Same day, update today's count
            logDailyCount(date: now, count: dailyKeyCount)
        } else {
            // Log the previous day's count
            logDailyCount(date: lastResetDate, count: dailyKeyCount)
            
            // Fill in any missing days
            fillMissingDays(from: lastResetDate, to: now)
            
            // Reset for the new day
            dailyKeyCount = 0
            UserDefaults.standard.set(dailyKeyCount, forKey: "dailyKeyCount")
        }
        
        // Update the last reset date
        UserDefaults.standard.set(now, forKey: "lastResetDate")
    }

    func logDailyCount(date: Date, count: Int) {
        let dateString = dateFormatter.string(from: date)
        let logEntry = "\(dateString),\(count)\n"
        
        if let logFileURL = getLogFileURL() {
            do {
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: logFileURL.path) {
                    guard let fileHandle = FileHandle(forUpdatingAtPath: logFileURL.path) else {
                        return
                    }
                    defer { fileHandle.closeFile() }
                    
                    // Seek to the end
                    fileHandle.seekToEndOfFile()
                    
                    // Get the current file size
                    let fileSize = fileHandle.offsetInFile
                    
                    var offset = fileSize - 1
                    var found = false
                    
                    if fileSize > 0 {
                        // Seek backwards to find the last newline
                        while offset > 0 {
                            fileHandle.seek(toFileOffset: offset)
                            if fileHandle.readData(ofLength: 1).first == 0x0A && offset < fileSize - 1 { // newline character
                                break
                            }
                            offset -= 1
                        }
                        
                        if (offset > 0 && offset < fileSize - 1) {
                            found = true
                        }
                    }
                        
                    if found {
                        // Read the last line
                        let lastLine = fileHandle.readDataToEndOfFile()
                        
                        if let lastLineString = String(data: lastLine, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                           lastLineString.hasPrefix(dateString) {
                            // Update the last line
                            fileHandle.seek(toFileOffset: offset + 1) // +1 to write after the newline
                            fileHandle.write(logEntry.data(using: .utf8)!)
                            fileHandle.truncateFile(atOffset: fileHandle.offsetInFile)
                        } else {
                            // Append new entry
                            fileHandle.seekToEndOfFile()
                            fileHandle.write(logEntry.data(using: .utf8)!)
                        }
                    } else {
                        // File is empty, just write the new entry
                        fileHandle.write(logEntry.data(using: .utf8)!)
                    }
                } else {
                    // Create new file with the entry
                    try logEntry.write(to: logFileURL, atomically: true, encoding: .utf8)
                }
            } catch {
                print("Error writing to log file: \(error)")
            }
        }
    }
    
    func fillMissingDays(from startDate: Date, to endDate: Date) {
        var currentDate = calendar.startOfDay(for: startDate)
        let targetEndDate = calendar.startOfDay(for: endDate)
        
        while currentDate < targetEndDate {
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
            if currentDate < targetEndDate {
                logDailyCount(date: currentDate, count: 0)
            }
        }
    }
    
    func getLogFileURL() -> URL? {
        return getSaveDir()?.appendingPathComponent("log.csv")
    }
    
    func getSaveDir() -> URL? {
        let fileManager = FileManager.default
        
        // Get the base directory URL
        if let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            
            // Create a subdirectory URL within the base directory
            let subdirectory = baseDirectory.appendingPathComponent("today.jason.howmanykeys")
            
            // Check if the subdirectory exists
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: subdirectory.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // Subdirectory already exists
                    return subdirectory
                }
            }
            
            // Create the subdirectory if it doesn't exist
            do {
                try fileManager.createDirectory(at: subdirectory, withIntermediateDirectories: true, attributes: nil)
                return subdirectory
            } catch {
                logger.error("Error creating subdirectory: \(error)")
            }
        }
        
        return nil
    }
    
    func applicationWillTerminate() {
        checkAndResetDailyCount()
    }
    
    func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 700, height: 104)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView:
            HistoryView(
                testMode: testMode,
                statusYear: Binding(
                    get: { self.currentYear },
                    set: { self.currentYear = $0 }
                ),
                currentDailyCount: self.dailyKeyCount,
                logFileURL: getLogFileURL()
           )
        )
        popover?.delegate = self
    }
    
    @objc func toggleHistory() {
        if let button = statusItem?.button, let popover = popover {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                isHistoryViewOpen = true
                updateStatusItemTitle()
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
    
    lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    func applicationWillTerminate(_ notification: Notification) {
        applicationWillTerminate()
    }
}

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        isHistoryViewOpen = false
        updateStatusItemTitle()
    }
}
