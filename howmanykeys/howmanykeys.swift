import SwiftUI
import Cocoa

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
    var statusItem: NSStatusItem?
    var eventMonitor: Any?
    var totalKeyCount: Int = UserDefaults.standard.integer(forKey: "totalKeyCount")
    var dailyKeyCount: Int = UserDefaults.standard.integer(forKey: "dailyKeyCount")
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
        dailyKeyCount = UserDefaults.standard.integer(forKey: "dailyKeyCount")
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
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] _ in
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
        
        if !calendar.isDate(lastResetDate, inSameDayAs: now) {
            // Log the previous day's count
            logDailyCount(date: lastResetDate, count: dailyKeyCount)
            
            // Fill in any missing days
            fillMissingDays(from: lastResetDate, to: now)
            
            // Reset for the new day
            dailyKeyCount = 0
            UserDefaults.standard.set(dailyKeyCount, forKey: "dailyKeyCount")
            UserDefaults.standard.set(now, forKey: "lastResetDate")
        }
    }
    
    func logDailyCount(date: Date, count: Int) {
        let dateString = dateFormatter.string(from: date)
        let logEntry = "\(dateString),\(count)\n"
        
        if let logFileURL = getLogFileURL(),
           let data = logEntry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                do {
                    let fileHandle = try FileHandle(forWritingTo: logFileURL)
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                } catch {
                    print("Error writing to log file: \(error)")
                }
            } else {
                do {
                    try data.write(to: logFileURL)
                } catch {
                    print("Error creating log file: \(error)")
                }
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
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsDirectory.appendingPathComponent("keystroke_log.csv")
    }
    
    func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 700, height: 104)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView:
            HistoryView(testMode: testMode,
                        statusYear: Binding(
                            get: { self.currentYear },
                            set: { self.currentYear = $0 }
                        ),
                        currentDailyCount: self.dailyKeyCount)  // Add this line
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
}

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        isHistoryViewOpen = false
        updateStatusItemTitle()
    }
}
