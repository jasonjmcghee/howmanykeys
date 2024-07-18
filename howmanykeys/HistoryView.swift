import SwiftUI

struct HistoryView: View {
    @State private var historicalData: [Date: Int] = [:]
    @State private var currentYear: Int
    @State private var minYear: Int?
    @State private var maxYear: Int?
    @Binding var statusYear: Int
    let currentDailyCount: Int
    
    let testMode: Bool
    
    init(testMode: Bool, statusYear: Binding<Int>, currentDailyCount: Int) {
        self.testMode = testMode
        self._currentYear = State(initialValue: Calendar.current.component(.year, from: Date()))
        self._statusYear = statusYear
        self.currentDailyCount = currentDailyCount
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                GitHubStyleCalendar(data: historicalData,
                                    year: currentYear,
                                    minYear: minYear ?? currentYear,
                                    maxYear: maxYear ?? currentYear,
                                    testMode: testMode,
                                    currentDailyCount: currentDailyCount,
                                    onYearChange: { newYear in
                                        currentYear = newYear
                                    })
                    .frame(width: geometry.size.width * 0.9, height: geometry.size.height * 0.83)
                    .padding(geometry.size.width * 0.025)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .offset(x: -8.0, y:0)
            .onChange(of: currentYear) { newYear in
                statusYear = newYear
                loadHistoricalData()
            }
            .onAppear(perform: {
                loadHistoricalData()
                determineYearRange()
                statusYear = currentYear
            })
        }.onChange(of: currentYear) { newYear in
            statusYear = newYear
        }
    }
    
    func loadHistoricalData() {
        if testMode {
            historicalData = generateTestData()
        } else {
            // Load actual data for the current year
            guard let logFileURL = (NSApplication.shared.delegate as? AppDelegate)?.getLogFileURL(),
                  let contents = try? String(contentsOf: logFileURL) else {
                return
            }
            
            let lines = contents.split(separator: "\n")
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            
            historicalData = [:]
            for line in lines {
                let parts = line.split(separator: ",")
                if parts.count == 2,
                   let date = dateFormatter.date(from: String(parts[0])),
                   Calendar.current.component(.year, from: date) == currentYear,
                   let count = Int(parts[1]) {
                    historicalData[date] = count
                }
            }
        }
    }
    
    func determineYearRange() {
        if testMode {
            minYear = currentYear - 2
            maxYear = currentYear + 2
        } else {
            guard let logFileURL = (NSApplication.shared.delegate as? AppDelegate)?.getLogFileURL(),
                  let contents = try? String(contentsOf: logFileURL) else {
                return
            }
            
            let lines = contents.split(separator: "\n")
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            
            let years = lines.compactMap { line -> Int? in
                let parts = line.split(separator: ",")
                if parts.count == 2,
                   let date = dateFormatter.date(from: String(parts[0])) {
                    return Calendar.current.component(.year, from: date)
                }
                return nil
            }
            
            minYear = years.min()
            maxYear = years.max()
        }
    }
    
    func generateTestData() -> [Date: Int] {
        var testData: [Date: Int] = [:]
        let calendar = Calendar.current
        let startDate = calendar.date(from: DateComponents(year: currentYear, month: 1, day: 1))!
        let endDate = calendar.date(from: DateComponents(year: currentYear, month: 12, day: 31))!
        
        var date = startDate
        while date <= endDate {
            testData[date] = Int.random(in: 0...500)
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        return testData
    }
}

struct GitHubStyleCalendar: View {
    let data: [Date: Int]
    @State var year: Int
    let minYear: Int
    let maxYear: Int
    let testMode: Bool
    let currentDailyCount: Int
    let onYearChange: (Int) -> Void
    let calendar = Calendar.current
    @State private var scrollOffset: CGFloat = 0
    @State private var previousScrollOffset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            let blockSize = min(geometry.size.width / 53, geometry.size.height / 7) * 0.9
            let spacing = blockSize * 0.2
            
            LazyHGrid(rows: Array(repeating: GridItem(.fixed(blockSize), spacing: spacing), count: 7), spacing: spacing) {
                ForEach(daysInYear(), id: \.self) { date in
                    colorBlock(for: date, size: blockSize)
                }
            }
        }
    }
    
    func daysInYear() -> [Date] {
        let startDate = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let endDate = calendar.date(from: DateComponents(year: year, month: 12, day: 31))!
        return calendar.generateDates(inside: DateInterval(start: startDate, end: endDate), matching: DateComponents(hour: 0, minute: 0, second: 0))
    }
    
    func colorBlock(for date: Date, size: CGFloat) -> some View {
            let count = isToday(date) ? currentDailyCount : (data[date] ?? 0)  // Update this line
            return RoundedRectangle(cornerRadius: size * 0.2)
                .strokeBorder(Color.purple.opacity(0.3), lineWidth: 1)
                .background(RoundedRectangle(cornerRadius: size * 0.2).fill(colorForCount(count)))
                .frame(width: size, height: size)
        }
        
    func isToday(_ date: Date) -> Bool {
        return calendar.isDateInToday(date)
    }
    
    func tooltipView(for date: Date) -> some View {
        let count = isToday(date) ? currentDailyCount : (data[date] ?? 0)  // Update this line
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy"
        let dateString = dateFormatter.string(from: date)
        
        return Text("\(count) keystrokes on \(dateString)")
            .padding(5)
            .background(Color.black.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(5)
    }
    
    func colorForCount(_ count: Int) -> Color {
        if count == 0 { return Color.clear }
        let maxCount = data.values.max() ?? 1
        let intensity = Double(count) / Double(maxCount)
        return Color.purple.opacity(intensity)
    }
    
    func showTooltip(at point: CGPoint, for date: Date, count: Int) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy"
        let dateString = dateFormatter.string(from: date)
        let tooltipString = "\(count) keystrokes on \(dateString)"
        
        let tooltip = NSText(frame: NSRect(x: point.x, y: point.y - 20, width: 200, height: 20))
        tooltip.string = tooltipString
        tooltip.backgroundColor = NSColor.black.withAlphaComponent(0.8)
        tooltip.textColor = NSColor.white
        tooltip.isEditable = false
        tooltip.isSelectable = false
        tooltip.font = NSFont.systemFont(ofSize: 12)
        tooltip.alignment = .center
        tooltip.sizeToFit()
        
        NSApplication.shared.mainWindow?.contentView?.addSubview(tooltip)
    }
    
    func hideTooltip() {
        NSApplication.shared.mainWindow?.contentView?.subviews.last?.removeFromSuperview()
    }
}

extension Calendar {
    func generateDates(inside interval: DateInterval, matching components: DateComponents) -> [Date] {
        var dates: [Date] = []
        dates.reserveCapacity(366)

        var date = interval.start
        while date <= interval.end {
            if let matchedDate = self.date(from: self.dateComponents([.year, .month, .day], from: date)) {
                dates.append(matchedDate)
            }
            date = self.date(byAdding: .day, value: 1, to: date)!
        }
        return dates
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
