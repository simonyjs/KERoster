//
//  MonthlyCalendarViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/02/04.
//

import UIKit

// MARK: - Dynamic Font Scaling
extension UIFont {
    static func scaledBoldFont(ofSize size: CGFloat) -> UIFont {
        let baseWidth: CGFloat = 834.0
        let screenWidth = UIScreen.main.bounds.width
        return UIFont.boldSystemFont(ofSize: size * (screenWidth / baseWidth))
    }

    static func scaledSystemFont(ofSize size: CGFloat) -> UIFont {
        let baseWidth: CGFloat = 834.0
        let screenWidth = UIScreen.main.bounds.width
        return UIFont.systemFont(ofSize: size * (screenWidth / baseWidth))
    }
}

// MARK: - MonthlyCalendarViewController
class MonthlyCalendarViewController: UIViewController,
                                     UICollectionViewDelegate,
                                     UICollectionViewDataSource,
                                     UICollectionViewDelegateFlowLayout {

    // MARK: - Stored Schedules
    /// UserDefaults 에 저장된 전체 스케줄
    var schedules: [String: [[String: String]]] = [:] {
        didSet { invalidateScheduleCaches() }
    }
    let schedulesUserDefaultsKey = "schedules"

    // Holiday DB ("yyyy-MM-dd" : title)
    var holidays: [String: String] = [:]

    // Current Month 기준
    var currentDate = Date()
    var calendar = Calendar.current

    // MARK: - Formatters (Lazy Cached)
    private lazy var dayDisplayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .init(identifier: "en_US_POSIX")
        f.dateFormat = "MMM dd"   // "Dec 25"
        return f
    }()

    private lazy var scheduleDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .init(identifier: "en_US_POSIX")
        f.dateFormat = "dd-MMM-yyyy"  // "25-Dec-2025"
        return f
    }()

    /// ✅ 공휴일 키 포맷터 (로컬 타임존 기준, yyyy-MM-dd)
    private lazy var holidayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone.current
        f.locale = .init(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Caches
    /// 날짜별 스케줄 캐시 (현재달 기준 이전/다음 달까지 포함)
    private var schedulesByDateCache: [Date: [[String: String]]] = [:]
    /// 날짜별 LAYOVER 여부 캐시
    private var layoverCache: [Date: Bool] = [:]
    /// DepDate 기준 전체 스케줄 정렬 (LAYOVER 계산용, 월 범위 제한 X)
    private var allSchedulesSorted: [[String: String]] = []
    /// 캐시 빌드 여부
    private var isScheduleCacheBuilt = false

    // MARK: - 캐시 무효화 & 빌드

    private func invalidateScheduleCaches() {
        isScheduleCacheBuilt = false
        schedulesByDateCache.removeAll()
        layoverCache.removeAll()
        allSchedulesSorted.removeAll()
    }

    /// currentDate 기준 -1개월 ~ +1개월 범위에 대해 날짜별 스케줄 캐시 구성
    private func buildScheduleCacheIfNeeded() {
        guard !isScheduleCacheBuilt else { return }
        isScheduleCacheBuilt = true

        schedulesByDateCache.removeAll()
        layoverCache.removeAll()
        allSchedulesSorted.removeAll()

        // 🔹 currentDate 기준 ±1개월 범위 계산
        guard let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: currentDate)) else {
            return
        }
        let prevMonthStart = calendar.date(byAdding: .month, value: -1, to: currentMonthStart) ?? currentMonthStart
        let nextNextMonthStart = calendar.date(byAdding: .month, value: 2, to: currentMonthStart) ?? currentMonthStart

        let rangeStart = calendar.startOfDay(for: prevMonthStart)              // 이전달 1일 00:00
        let rangeEnd = calendar.date(byAdding: .day, value: -1, to: nextNextMonthStart)
            .map { calendar.startOfDay(for: $0) } ?? rangeStart                // 다음달 말일 00:00

        // 1) 전체 스케줄 수집
        var collected: [[String: String]] = []
        for (_, arr) in schedules {
            collected.append(contentsOf: arr)
        }

        // 2) DepDate 기준 정렬 (LAYOVER 계산용)
        collected.sort {
            let d1 = scheduleDateFormatter.date(from: $0["DepDate"] ?? "") ?? .distantPast
            let d2 = scheduleDateFormatter.date(from: $1["DepDate"] ?? "") ?? .distantPast
            return d1 < d2
        }
        allSchedulesSorted = collected    // Layover 계산은 전체 사용

        // 3) 날짜별 캐시 구성 (±1개월 범위 안에 들어오는 날짜만)
        for s in collected {
            guard let depStr = s["DepDate"],
                  let depDate = scheduleDateFormatter.date(from: depStr) else { continue }

            // ArrDate / DutyDebriefDate 파싱
            var arrDate: Date? = nil
            if let arrStr = (s["ArrDate"] ?? s["DutyDebriefDate"]),
               let a = scheduleDateFormatter.date(from: arrStr) {
                arrDate = a
            }

            if let arr = arrDate {
                // 일정 전체 범위
                let earliest = min(depDate, arr)
                let latest = max(depDate, arr)

                // ±1개월 범위와 겹치지 않으면 skip
                if latest < rangeStart || earliest > rangeEnd { continue }

                if depDate > arr {
                    // Dep > Arr: 출발일/도착일만 표시
                    if depDate >= rangeStart && depDate <= rangeEnd {
                        addSchedule(s, on: depDate)
                    }
                    if arr >= rangeStart && arr <= rangeEnd {
                        addSchedule(s, on: arr)
                    }
                } else {
                    // Dep ~ Arr 사이 모든 날짜 (±1개월 범위로 클램프)
                    var day = max(depDate, rangeStart)
                    let end = min(arr, rangeEnd)

                    while day <= end {
                        addSchedule(s, on: day)
                        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                        day = next
                    }
                }
            } else {
                // ArrDate/DutyDebriefDate가 없으면 DepDate 하루만
                if depDate >= rangeStart && depDate <= rangeEnd {
                    addSchedule(s, on: depDate)
                }
            }
        }
    }

    private func addSchedule(_ schedule: [String: String], on date: Date) {
        let key = calendar.startOfDay(for: date)
        schedulesByDateCache[key, default: []].append(schedule)
    }

    // MARK: Owner / Hours
    let ownerUserDefaultsKey = "ownerInfo"
    let totalHoursByMonthUserDefaultsKey = "totalHoursByMonth"
    var ownerInfo = ""
    var totalHours = ""

    func formattedMonth(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: date)
    }

    // MARK: UI
    let monthControlView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    /// 중앙에 크게 나오는 "December 2025"
    let monthLabel: UILabel = {
        let l = UILabel()
        l.font = .scaledBoldFont(ofSize: 22)
        l.textAlignment = .center
        l.textColor = .black
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    /// 좌측 "YOON JUNGSUB | 1203720 | 32S | ICN | CAP"
    let ownerInfoLabel: UILabel = {
        let l = UILabel()
        l.font = .scaledBoldFont(ofSize: 8)
        l.textColor = .black
        l.textAlignment = .left
        l.translatesAutoresizingMaskIntoConstraints = false
        l.numberOfLines = 1
        return l
    }()

    /// 우측 "FLY 40:35 TVL 01:05 DO 10 RESERVE 3"
    let totalHoursLabel: UILabel = {
        let l = UILabel()
        l.font = .scaledBoldFont(ofSize: 8)
        l.textColor = .black
        l.textAlignment = .right
        l.translatesAutoresizingMaskIntoConstraints = false
        l.numberOfLines = 1
        return l
    }()

    let prevButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(
            UIImage(systemName: "arrowshape.backward.circle.fill")?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        b.tintColor = UIColor(named: "Ocean")
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    let nextButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(
            UIImage(systemName: "arrowshape.forward.circle.fill")?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        b.tintColor = UIColor(named: "Ocean")
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .white
        return cv
    }()

    let daysOfWeek = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    // MARK: - viewDidLoad
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        setupViews()
        setupConstraints()

        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(CalendarDayCell.self, forCellWithReuseIdentifier: "dayCell")

        updateMonthLabel()
        loadOwnerInfo()
        loadSchedules()
        loadTotalHours()
        fetchHolidays(for: currentDate)

        buildScheduleCacheIfNeeded()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(timeZoneChanged(_:)),
            name: .NSSystemTimeZoneDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // 회전 시 셀 사이즈 재계산
    override func viewWillTransition(to size: CGSize,
                                     with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.collectionView.collectionViewLayout.invalidateLayout()
        }, completion: nil)
    }

    @objc private func timeZoneChanged(_ n: Notification) {
        calendar = Calendar.current
        holidayKeyFormatter.timeZone = calendar.timeZone
        invalidateScheduleCaches()
        collectionView.reloadData()
    }

    // MARK: - Setup Views / Constraints

    func setupViews() {
        view.addSubview(monthControlView)
        view.addSubview(collectionView)

        monthControlView.addSubview(prevButton)
        monthControlView.addSubview(nextButton)
        monthControlView.addSubview(monthLabel)
        monthControlView.addSubview(ownerInfoLabel)
        monthControlView.addSubview(totalHoursLabel)

        prevButton.addTarget(self, action: #selector(prevMonth), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextMonth), for: .touchUpInside)

        // 월/연도 라벨이 항상 가운데 잘 보이도록 우선순위
        monthLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        monthLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        ownerInfoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        totalHoursLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    func setupConstraints() {
        let safe = view.safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            monthControlView.topAnchor.constraint(equalTo: safe.topAnchor),
            monthControlView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            monthControlView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            monthControlView.heightAnchor.constraint(equalToConstant: 56),

            // 좌우 화살표 버튼
            prevButton.leadingAnchor.constraint(equalTo: monthControlView.leadingAnchor, constant: 12),
            prevButton.centerYAnchor.constraint(equalTo: monthControlView.centerYAnchor),
            prevButton.widthAnchor.constraint(equalToConstant: 34),
            prevButton.heightAnchor.constraint(equalToConstant: 34),

            nextButton.trailingAnchor.constraint(equalTo: monthControlView.trailingAnchor, constant: -12),
            nextButton.centerYAnchor.constraint(equalTo: monthControlView.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 34),
            nextButton.heightAnchor.constraint(equalToConstant: 34),

            // 중앙 월/연도
            monthLabel.centerXAnchor.constraint(equalTo: monthControlView.centerXAnchor),
            monthLabel.centerYAnchor.constraint(equalTo: monthControlView.centerYAnchor),

            // 왼쪽 소유자 정보
            ownerInfoLabel.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: 8),
            ownerInfoLabel.centerYAnchor.constraint(equalTo: monthControlView.centerYAnchor),
            ownerInfoLabel.trailingAnchor.constraint(lessThanOrEqualTo: monthLabel.leadingAnchor, constant: -8),

            // 오른쪽 총 비행시간
            totalHoursLabel.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -8),
            totalHoursLabel.centerYAnchor.constraint(equalTo: monthControlView.centerYAnchor),
            totalHoursLabel.leadingAnchor.constraint(greaterThanOrEqualTo: monthLabel.trailingAnchor, constant: 8),

            // 달력
            collectionView.topAnchor.constraint(equalTo: monthControlView.bottomAnchor, constant: 4),
            collectionView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: safe.bottomAnchor)
        ])
    }

    // MARK: Loaders
    func loadOwnerInfo() {
        if let v = UserDefaults.standard.string(forKey: ownerUserDefaultsKey) {
            ownerInfo = v
            ownerInfoLabel.text = v
        }
    }

    func loadSchedules() {
        if let d = UserDefaults.standard.dictionary(forKey: schedulesUserDefaultsKey)
            as? [String: [[String: String]]] {
            schedules = d
        }
    }

    func loadTotalHours() {
        if let d = UserDefaults.standard.dictionary(forKey: totalHoursByMonthUserDefaultsKey)
            as? [String: String] {
            totalHours = d[formattedMonth(for: currentDate)] ?? ""
            totalHoursLabel.text = totalHours
        } else {
            totalHours = ""
            totalHoursLabel.text = ""
        }
    }

    func updateMonthLabel() {
        let f = DateFormatter()
        f.locale = .init(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM yyyy" // "December 2025"
        monthLabel.text = f.string(from: currentDate)
    }

    // MARK: Month Move
    @objc func prevMonth() {
        currentDate = calendar.date(byAdding: .month, value: -1, to: currentDate) ?? currentDate
        invalidateScheduleCaches()
        updateMonthLabel()
        loadTotalHours()
        fetchHolidays(for: currentDate)
        collectionView.reloadData()
    }

    @objc func nextMonth() {
        currentDate = calendar.date(byAdding: .month, value: 1, to: currentDate) ?? currentDate
        invalidateScheduleCaches()
        updateMonthLabel()
        loadTotalHours()
        fetchHolidays(for: currentDate)
        collectionView.reloadData()
    }

    // MARK: - Holiday Fetch (기존 동작과 동일하게, 날짜 밀림 방지)
    func fetchHolidays(for date: Date) {
        holidays.removeAll()

        guard let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
        else { return }

        let startDate = firstDayOfMonth
        var comp = DateComponents()
        comp.month = 1
        comp.second = -1
        guard let endDate = calendar.date(byAdding: comp, to: firstDayOfMonth) else { return }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let timeMin = isoFormatter.string(from: startDate)
        let timeMax = isoFormatter.string(from: endDate)

        let apiKey = "AIzaSyBz8S4W3GWLukQ-etLQBlWUP385pPlFunY"
        let calendarId = "ko.south_korea.official%23holiday%40group.v.calendar.google.com"
        let urlString =
        "https://www.googleapis.com/calendar/v3/calendars/\(calendarId)/events?key=\(apiKey)&orderBy=startTime&singleEvents=true&timeMin=\(timeMin)&timeMax=\(timeMax)"

        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self else { return }
            if let error = error {
                print("Holiday API error: \(error.localizedDescription)")
                return
            }
            guard let data = data else { return }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]] {

                for item in items {
                    if let startInfo = item["start"] as? [String: Any],
                       let dateStr = startInfo["date"] as? String,   // "yyyy-MM-dd"
                       let title = item["summary"] as? String {
                        // 그대로 저장 (UTC 변환 X)
                        self.holidays[dateStr] = title
                    }
                }

                DispatchQueue.main.async {
                    self.collectionView.reloadData()
                }
            }
        }.resume()
    }

    // MARK: Layover Cache
    func shouldDisplayLayover(for date: Date) -> Bool {
        let key = calendar.startOfDay(for: date)
        if let c = layoverCache[key] { return c }

        buildScheduleCacheIfNeeded()

        var result = false

        for (i, s) in allSchedulesSorted.enumerated() {
            guard let hotel = s["Hotel"], !hotel.isEmpty,
                  let arrStr = s["ArrDate"],
                  let arr = scheduleDateFormatter.date(from: arrStr),
                  let start = calendar.date(byAdding: .day, value: 1, to: arr)
            else { continue }

            let startDay = calendar.startOfDay(for: start)

            var endDay: Date?
            if i < allSchedulesSorted.count - 1 {
                if let nextDepStr = allSchedulesSorted[i + 1]["DepDate"],
                   let nextDep = scheduleDateFormatter.date(from: nextDepStr),
                   let e = calendar.date(byAdding: .day, value: -1, to: nextDep) {
                    endDay = calendar.startOfDay(for: e)
                }
            }

            let day = key
            if let e = endDay {
                if day >= startDay && day <= e { result = true; break }
            } else {
                if day >= startDay { result = true; break }
            }
        }

        layoverCache[key] = result
        return result
    }

    // MARK: CollectionView DataSource
    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int { return 49 }

    // MARK: cellForItemAt
    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: "dayCell",
            for: indexPath
        ) as! CalendarDayCell

        let isiPhone = UIDevice.current.userInterfaceIdiom == .phone
        let isLand = view.bounds.width > view.bounds.height

        // Header Row (요일)
        if indexPath.item < 7 {
            cell.isHeader = true
            cell.dateLabel.text = daysOfWeek[indexPath.item]
            cell.dateLabel.font = .boldSystemFont(ofSize: (isiPhone && isLand) ? 6 : 10)
            return cell
        }

        // 날짜 셀
        cell.isHeader = false
        cell.scheduleStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let comp = calendar.dateComponents([.year, .month], from: currentDate)
        guard let firstDay = calendar.date(from: comp) else { return cell }

        let weekday = calendar.component(.weekday, from: firstDay)
        var offset = weekday - calendar.firstWeekday
        if offset < 0 { offset += 7 }

        let index = indexPath.item - 7
        let dayNumber = index - offset + 1

        let range = calendar.range(of: .day, in: .month, for: currentDate)!
        let monthDays = range.count

        var dateForCell: Date?
        var textColor: UIColor = .black

        // 이전 달
        if dayNumber < 1 {
            if let prevMonth = calendar.date(byAdding: .month, value: -1, to: currentDate),
               let prevRange = calendar.range(of: .day, in: .month, for: prevMonth) {
                let d = prevRange.count + dayNumber
                var c = calendar.dateComponents([.year, .month], from: prevMonth)
                c.day = d
                dateForCell = calendar.date(from: c)
                cell.contentView.backgroundColor = UIColor(named: "LightGreen")
                textColor = UIColor(named: "DarkGreen") ?? .green
            }
        }
        // 다음 달
        else if dayNumber > monthDays {
            if let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentDate) {
                let d = dayNumber - monthDays
                var c = calendar.dateComponents([.year, .month], from: nextMonth)
                c.day = d
                dateForCell = calendar.date(from: c)
                cell.contentView.backgroundColor = UIColor(named: "LightGreen")
                textColor = UIColor(named: "DarkGreen") ?? .green
            }
        }
        // 현재 달
        else {
            var c = calendar.dateComponents([.year, .month], from: currentDate)
            c.day = dayNumber
            dateForCell = calendar.date(from: c)
            cell.contentView.backgroundColor = .white
            textColor = .black
        }

        guard let validDate = dateForCell else { return cell }

        // 날짜 라벨
        let dateText = dayDisplayFormatter.string(from: validDate)
        let dateFontSize: CGFloat = (isiPhone && isLand) ? 7 : 10

        if calendar.isDate(validDate, inSameDayAs: Date()) {
            cell.dateLabel.text = dateText
            cell.dateLabel.font = .boldSystemFont(ofSize: dateFontSize)
            cell.dateLabel.textColor = .white
            cell.dateLabel.backgroundColor = .red
            cell.dateLabel.layer.cornerRadius = 4
            cell.dateLabel.clipsToBounds = true
        } else {
            cell.dateLabel.text = dateText
            cell.dateLabel.font = .boldSystemFont(ofSize: dateFontSize)
            cell.dateLabel.textColor = textColor
            cell.dateLabel.backgroundColor = .clear
        }

        // 공휴일 처리 (스케줄은 그대로, 라벨만 [타이틀] 추가)
        let holidayKey = holidayKeyFormatter.string(from: validDate)   // ✅ 로컬 타임존 기준
        if let holidayTitle = holidays[holidayKey] {
            cell.contentView.backgroundColor = UIColor(named: "LightYellow")
            cell.dateLabel.text = "\(dateText) [\(holidayTitle)]"
            cell.dateLabel.textColor = UIColor(named: "DarkYellow") ?? .orange
        }

        // 날짜별 스케줄 캐시 조회
        buildScheduleCacheIfNeeded()
        let key = calendar.startOfDay(for: validDate)
        var schedulesForCell = schedulesByDateCache[key] ?? []

        // DepDate 순으로 정렬
        schedulesForCell.sort {
            let d1 = scheduleDateFormatter.date(from: $0["DepDate"] ?? "") ?? .distantPast
            let d2 = scheduleDateFormatter.date(from: $1["DepDate"] ?? "") ?? .distantPast
            return d1 < d2
        }

        // SDC (첫 줄만)
        if let sdcSchedule = schedulesForCell.first(where: { ($0["SDC"] ?? "").isEmpty == false }),
           let sdcValue = sdcSchedule["SDC"] {

            let label = UILabel()
            label.font = .boldSystemFont(ofSize: (isiPhone && isLand) ? 5 : 8)
            label.textColor = textColor
            label.text = "🛑 [\(sdcValue)]"
            label.numberOfLines = 0
            cell.scheduleStackView.addArrangedSubview(label)
        }

        // 스케줄 표시
        for s in schedulesForCell {
            let label = UILabel()
            label.font = .boldSystemFont(ofSize: (isiPhone && isLand) ? 5 : 8)
            label.textColor = textColor
            label.numberOfLines = 0

            var line = ""
            let wt = (s["WorkType"] ?? "").uppercased()

            if wt == "FLY" || wt == "TVL" {
                var item = s["Item"] ?? ""
                if wt == "TVL" {
                    if item.count >= 2 { item = "DH" + item.dropFirst(2) }
                    else { item = "DH" }
                }

                let depT = s["DepStnTime"] ?? ""
                let arrT = s["ArrStnTime"] ?? ""
                let depAp = s["DepAp"] ?? ""
                let arrAp = s["ArrAp"] ?? ""

                guard let depDate = scheduleDateFormatter.date(from: s["DepDate"] ?? ""),
                      let arrDate = scheduleDateFormatter.date(from: s["ArrDate"] ?? s["DutyDebriefDate"] ?? "")
                else { continue }

                let overnight = !calendar.isDate(depDate, inSameDayAs: arrDate)

                if overnight {
                    if calendar.isDate(validDate, inSameDayAs: depDate) {
                        line = "\(item) \(depT) \(depAp) - \(arrAp) 23:59"
                    } else if calendar.isDate(validDate, inSameDayAs: arrDate) {
                        line = "\(item) 00:00 \(depAp) - \(arrAp) \(arrT)"
                    }
                } else {
                    line = "\(item) \(depT) \(depAp) - \(arrAp) \(arrT)"
                }
            } else {
                let act = s["Activity"] ?? ""
                let dr = s["DutyReport"] ?? ""
                let rawDD = s["DutyDebrief"] ?? ""
                let dd = rawDD.components(separatedBy: "(").first?
                    .trimmingCharacters(in: .whitespaces) ?? rawDD

                if let depDate = scheduleDateFormatter.date(from: s["DepDate"] ?? ""),
                   let ddDate = scheduleDateFormatter.date(from: s["DutyDebriefDate"] ?? "") {

                    let sameDay = calendar.isDate(depDate, inSameDayAs: ddDate)

                    if sameDay {
                        line = "\(act) \(dr) - \(dd)"
                    } else {
                        if calendar.isDate(validDate, inSameDayAs: depDate) {
                            line = "\(act) \(dr) - 23:59"
                        } else if calendar.isDate(validDate, inSameDayAs: ddDate) {
                            line = "\(act) 00:00 - \(dd)"
                        }
                    }
                } else {
                    line = "\(act) \(dr) - \(dd)"
                }

                // WT 없고 00:00 ~ 23:59 인 "하루 종일" 근무 → Item/Activity만
                let allDay =
                    wt.isEmpty &&
                    dr.hasPrefix("00:00") &&
                    dd.hasPrefix("23:59")

                if allDay {
                    let itemText = (s["Item"] ?? "").trimmingCharacters(in: .whitespaces)
                    if !itemText.isEmpty {
                        line = itemText
                    } else if !act.trimmingCharacters(in: .whitespaces).isEmpty {
                        line = act
                    }
                }
            }

            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                label.text = line
                cell.scheduleStackView.addArrangedSubview(label)
            }
        }

        // 스케줄이 없고, LAYOVER 인 경우
        if schedulesForCell.isEmpty, shouldDisplayLayover(for: validDate) {
            let l = UILabel()
            l.font = .boldSystemFont(ofSize: (isiPhone && isLand) ? 5 : 8)
            l.textColor = textColor
            l.text = "LAYOVER"
            cell.scheduleStackView.addArrangedSubview(l)
        }

        return cell
    }

    // MARK: - Size
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {

        guard let flow = collectionViewLayout as? UICollectionViewFlowLayout else {
            return .zero
        }
        let inset = flow.sectionInset
        let spacing = flow.minimumInteritemSpacing
        let total = inset.left + inset.right + spacing * 6
        let cellW = floor((collectionView.frame.width - total) / 7)

        let isiPhone = UIDevice.current.userInterfaceIdiom == .phone
        let isLand = view.bounds.width > view.bounds.height
        let headerH: CGFloat = (isiPhone && isLand) ? 20 : 30

        if indexPath.item < 7 {
            return CGSize(width: cellW, height: headerH)
        }

        let lineSpacing = flow.minimumLineSpacing
        let totalH = inset.top + inset.bottom + headerH + lineSpacing * 5
        let availH = collectionView.frame.height - totalH
        return CGSize(width: cellW, height: availH / 6)
    }

    // MARK: - DidSelect
    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {

        guard indexPath.item >= 7 else { return }

        let comp = calendar.dateComponents([.year, .month], from: currentDate)
        guard let first = calendar.date(from: comp) else { return }

        let weekday = calendar.component(.weekday, from: first)
        var offset = weekday - calendar.firstWeekday
        if offset < 0 { offset += 7 }

        let idx = indexPath.item - 7
        let dayNum = idx - offset + 1
        let range = calendar.range(of: .day, in: .month, for: currentDate)!
        let monthDays = range.count

        var selectedDate: Date?
        if dayNum < 1 {
            if let prevM = calendar.date(byAdding: .month, value: -1, to: currentDate),
               let prevRange = calendar.range(of: .day, in: .month, for: prevM) {
                let d = prevRange.count + dayNum
                var c = calendar.dateComponents([.year, .month], from: prevM)
                c.day = d
                selectedDate = calendar.date(from: c)
            }
        } else if dayNum > monthDays {
            if let nextM = calendar.date(byAdding: .month, value: 1, to: currentDate) {
                let d = dayNum - monthDays
                var c = calendar.dateComponents([.year, .month], from: nextM)
                c.day = d
                selectedDate = calendar.date(from: c)
            }
        } else {
            var c = calendar.dateComponents([.year, .month], from: currentDate)
            c.day = dayNum
            selectedDate = calendar.date(from: c)
        }

        guard let date = selectedDate else { return }

        let f = DateFormatter()
        f.dateFormat = "dd-MMM-yyyy"
        let target = f.string(from: date)

        var result: [[String: String]] = []
        for (_, arr) in schedules {
            for s in arr {
                if s["DepDate"] == target { result.append(s) }
                else if s["ArrDate"] == target { result.append(s) }
            }
        }

        let sb = UIStoryboard(name: "Main", bundle: nil)
        if let vc = sb.instantiateViewController(withIdentifier: "ScheduleDetailViewController")
            as? ScheduleDetailViewController {

            vc.selectedDate = target
            vc.scheduleDetailsList = result
            vc.modalPresentationStyle = .formSheet
            present(vc, animated: true)
        }
    }
}

// MARK: - CalendarDayCell
class CalendarDayCell: UICollectionViewCell {

    let dateLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    let scheduleStackView: UIStackView = {
        let v = UIStackView()
        v.axis = .vertical
        v.spacing = 2
        v.alignment = .leading
        v.distribution = .fill
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    var isHeader = false {
        didSet { updateMode() }
    }

    private var normalConstraints: [NSLayoutConstraint] = []
    private var headerConstraints: [NSLayoutConstraint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.layer.borderWidth = 0.2
        contentView.layer.borderColor = UIColor(named: "Ocean")?.cgColor

        contentView.addSubview(dateLabel)
        contentView.addSubview(scheduleStackView)

        normalConstraints = [
            dateLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            dateLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),

            scheduleStackView.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 2),
            scheduleStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            scheduleStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            scheduleStackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -2)
        ]

        headerConstraints = [
            dateLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            dateLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ]

        updateMode()
    }

    private func updateMode() {
        if isHeader {
            NSLayoutConstraint.deactivate(normalConstraints)
            NSLayoutConstraint.activate(headerConstraints)
            scheduleStackView.isHidden = true
            dateLabel.textAlignment = .center
        } else {
            NSLayoutConstraint.deactivate(headerConstraints)
            NSLayoutConstraint.activate(normalConstraints)
            scheduleStackView.isHidden = false
            dateLabel.textAlignment = .left
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        contentView.backgroundColor = .clear
        dateLabel.backgroundColor = .clear
        dateLabel.textColor = .black
        scheduleStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        isHeader = false
    }

    required init?(coder: NSCoder) {
        fatalError()
    }
}
