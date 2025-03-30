//
//  MonthlyCalendarViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/02/04.
//

import UIKit

// MARK: - 폰트 동적 스케일링을 위한 UIFont Extension
extension UIFont {
    static func scaledBoldFont(ofSize size: CGFloat) -> UIFont {
        let baseWidth: CGFloat = 834.0
        let screenWidth = UIScreen.main.bounds.width
        let scaleFactor = screenWidth / baseWidth
        return UIFont.boldSystemFont(ofSize: size * scaleFactor)
    }
    
    static func scaledSystemFont(ofSize size: CGFloat) -> UIFont {
        let baseWidth: CGFloat = 834.0
        let screenWidth = UIScreen.main.bounds.width
        let scaleFactor = screenWidth / baseWidth
        return UIFont.systemFont(ofSize: size * scaleFactor)
    }
}

// MARK: - MonthlyCalendarViewController
class MonthlyCalendarViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    // 스케줄 데이터 (날짜별로 스케줄 목록 저장)
    var schedules: [String: [[String: String]]] = [:]
    let schedulesUserDefaultsKey = "schedules"
    
    // 휴일 정보: API에서 받은 "yyyy-MM-dd" 문자열을 키로 사용
    var holidays: [String: String] = [:]
    
    // 현재 선택된 날짜(달)
    var currentDate = Date()
    // 시스템 시간대 변경에 따른 최신 정보를 반영하기 위해 calendar를 재할당할 수 있도록 함
    var calendar = Calendar.current
    
    // 소유자 정보와 총 시간 정보
    var ownerInfo: String = ""
    var totalHours: String = ""
    
    // UserDefaults Key들
    let ownerUserDefaultsKey = "ownerInfo"
    let totalHoursByMonthUserDefaultsKey = "totalHoursByMonth"
    
    // MARK: - 헬퍼 함수: 현재 날짜의 "yyyy-MM" 포맷 문자열 반환
    func formattedMonth(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
    
    // MARK: - UI Elements
    let monthControlView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let prevButton: UIButton = {
        let button = UIButton(type: .system)
        if let image = UIImage(systemName: "arrowshape.backward.circle.fill")?.withRenderingMode(.alwaysTemplate) {
            button.setImage(image, for: .normal)
        }
        button.tintColor = UIColor(named: "Ocean")
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    let nextButton: UIButton = {
        let button = UIButton(type: .system)
        if let image = UIImage(systemName: "arrowshape.forward.circle.fill")?.withRenderingMode(.alwaysTemplate) {
            button.setImage(image, for: .normal)
        }
        button.tintColor = UIColor(named: "Ocean")
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    let monthLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.scaledBoldFont(ofSize: 20)
        label.textAlignment = .center
        label.textColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let ownerLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.scaledSystemFont(ofSize: 10)
        label.textAlignment = .center
        label.textColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let totalHoursLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.scaledSystemFont(ofSize: 10)
        label.textAlignment = .center
        label.textColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let monthStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.alignment = .center
        sv.distribution = .equalCentering
        sv.spacing = 8
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    
    let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 1
        layout.minimumInteritemSpacing = 1
        layout.sectionInset = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        layout.scrollDirection = .vertical
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .white
        cv.register(CalendarDayCell.self, forCellWithReuseIdentifier: "dayCell")
        cv.isScrollEnabled = false
        return cv
    }()
    
    // 요일 배열
    var daysOfWeek: [String] {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
        } else {
            return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        }
    }
    
    // 제약조건 변수
    var monthControlHeightConstraint: NSLayoutConstraint!
    var collectionViewTopConstraint: NSLayoutConstraint!
    
    // MARK: - View LifeCycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        navigationItem.title = "ROSTER SUMMARY"
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(systemTimeZoneDidChange),
                                               name: NSNotification.Name.NSSystemTimeZoneDidChange,
                                               object: nil)
        
        if schedules.isEmpty {
            loadSchedules()
        }
        
        if let savedOwner = UserDefaults.standard.string(forKey: ownerUserDefaultsKey) {
            self.ownerInfo = savedOwner
        }
        
        if let monthlyHours = UserDefaults.standard.dictionary(forKey: totalHoursByMonthUserDefaultsKey) as? [String: String] {
            let currentMonthKey = formattedMonth(for: currentDate)
            self.totalHours = monthlyHours[currentMonthKey] ?? ""
        }
        
        calendar.firstWeekday = 1
        
        view.addSubview(monthControlView)
        monthControlView.addSubview(monthStackView)
        monthStackView.addArrangedSubview(prevButton)
        monthStackView.addArrangedSubview(ownerLabel)
        monthStackView.addArrangedSubview(monthLabel)
        monthStackView.addArrangedSubview(totalHoursLabel)
        monthStackView.addArrangedSubview(nextButton)
        
        prevButton.addTarget(self, action: #selector(prevMonth), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextMonth), for: .touchUpInside)
        
        view.addSubview(collectionView)
        collectionView.delegate = self
        collectionView.dataSource = self
        
        setupConstraints()
        updateLayoutForOrientation(size: view.bounds.size)
        updateMonthLabel()
        
        ownerLabel.text = ownerInfo
        totalHoursLabel.text = totalHours
        
        fetchHolidays(for: currentDate)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadSchedules() // 최신 스케줄을 불러옴
        collectionView.reloadData() // UI 업데이트
        if let monthlyHours = UserDefaults.standard.dictionary(forKey: totalHoursByMonthUserDefaultsKey) as? [String: String] {
            let currentMonthKey = formattedMonth(for: currentDate)
            self.totalHours = monthlyHours[currentMonthKey] ?? ""
        } else {
            self.totalHours = ""
        }
        totalHoursLabel.text = totalHours
        collectionView.reloadData()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.preferredContentSize = self.view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.updateLayoutForOrientation(size: size)
            self.collectionView.collectionViewLayout.invalidateLayout()
            self.view.layoutIfNeeded()
        }, completion: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil)
    }
    
    @objc func systemTimeZoneDidChange(notification: Notification) {
        print("시스템 시간대 변경 – 내부 재설정")
        calendar = Calendar.current
        calendar.firstWeekday = 1
        currentDate = Date()
        updateMonthLabel()
        fetchHolidays(for: currentDate)
        collectionView.reloadData()
    }
    
    func loadSchedules() {
        if let sharedDefaults = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster"),
           let data = sharedDefaults.data(forKey: schedulesUserDefaultsKey) {
            do {
                schedules = try JSONDecoder().decode([String: [[String: String]]].self, from: data)
                print("스케줄 로드 성공")
            } catch {
                print("스케줄 불러오기 실패: \(error)")
            }
        } else {
            print("저장된 스케줄 없음")
        }
    }
    
    func setupConstraints() {
        monthControlHeightConstraint = monthControlView.heightAnchor.constraint(equalToConstant: 40)
        collectionViewTopConstraint = collectionView.topAnchor.constraint(equalTo: monthControlView.bottomAnchor, constant: 10)
        
        NSLayoutConstraint.activate([
            monthControlView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            monthControlView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            monthControlView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            monthControlHeightConstraint,
            
            monthStackView.topAnchor.constraint(equalTo: monthControlView.topAnchor),
            monthStackView.bottomAnchor.constraint(equalTo: monthControlView.bottomAnchor),
            monthStackView.leadingAnchor.constraint(equalTo: monthControlView.leadingAnchor, constant: 10),
            monthStackView.trailingAnchor.constraint(equalTo: monthControlView.trailingAnchor, constant: -10),
            
            collectionViewTopConstraint,
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    func updateLayoutForOrientation(size: CGSize) {
        let isLandscape = size.width > size.height
        let isiPhone = UIDevice.current.userInterfaceIdiom == .phone
        
        if isiPhone && isLandscape {
            monthControlHeightConstraint.constant = 20
            collectionViewTopConstraint.constant = 2
            monthLabel.font = UIFont.scaledBoldFont(ofSize: 14)
            ownerLabel.font = UIFont.scaledSystemFont(ofSize: 7)
            totalHoursLabel.font = UIFont.scaledSystemFont(ofSize: 7)
        } else {
            monthControlHeightConstraint.constant = 40
            collectionViewTopConstraint.constant = 10
            monthLabel.font = UIFont.scaledBoldFont(ofSize: 20)
            ownerLabel.font = UIFont.scaledSystemFont(ofSize: 10)
            totalHoursLabel.font = UIFont.scaledSystemFont(ofSize: 10)
        }
    }
    
    func updateMonthLabel() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM yyyy"
        monthLabel.text = formatter.string(from: currentDate)
    }
    
    func fetchHolidays(for date: Date) {
        holidays.removeAll()
        guard let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) else { return }
        let startDate = firstDayOfMonth
        var components = DateComponents()
        components.month = 1
        components.second = -1
        guard let endDate = calendar.date(byAdding: components, to: firstDayOfMonth) else { return }
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let timeMin = isoFormatter.string(from: startDate)
        let timeMax = isoFormatter.string(from: endDate)
        
        let apiKey = "AIzaSyBz8S4W3GWLukQ-etLQBlWUP385pPlFunY"
        let calendarId = "ko.south_korea.official%23holiday%40group.v.calendar.google.com"
        let urlString = "https://www.googleapis.com/calendar/v3/calendars/\(calendarId)/events?key=\(apiKey)&orderBy=startTime&singleEvents=true&timeMin=\(timeMin)&timeMax=\(timeMax)"
        
        guard let url = URL(string: urlString) else {
            print("URL 생성 실패")
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                print("API 요청 오류: \(error.localizedDescription)")
                return
            }
            guard let data = data else {
                print("데이터 없음")
                return
            }
            do {
                if let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let items = jsonObject["items"] as? [[String: Any]] {
                    for item in items {
                        if let startInfo = item["start"] as? [String: Any],
                           let startDateStr = startInfo["date"] as? String,
                           let summary = item["summary"] as? String {
                            print("휴일: \(startDateStr) - \(summary)")
                            self.holidays[startDateStr] = summary
                        }
                    }
                    DispatchQueue.main.async {
                        self.collectionView.reloadData()
                    }
                } else {
                    print("JSON 응답 형식 오류")
                }
            } catch {
                print("JSON 파싱 오류: \(error.localizedDescription)")
            }
        }
        task.resume()
    }
    
    @objc func prevMonth() {
        currentDate = calendar.date(byAdding: .month, value: -1, to: currentDate) ?? currentDate
        updateMonthLabel()
        fetchHolidays(for: currentDate)
        collectionView.reloadData()
        if let monthlyHours = UserDefaults.standard.dictionary(forKey: totalHoursByMonthUserDefaultsKey) as? [String: String] {
            let currentMonthKey = formattedMonth(for: currentDate)
            self.totalHours = monthlyHours[currentMonthKey] ?? ""
        } else {
            self.totalHours = ""
        }
        totalHoursLabel.text = totalHours
    }
    
    @objc func nextMonth() {
        currentDate = calendar.date(byAdding: .month, value: 1, to: currentDate) ?? currentDate
        updateMonthLabel()
        fetchHolidays(for: currentDate)
        collectionView.reloadData()
        if let monthlyHours = UserDefaults.standard.dictionary(forKey: totalHoursByMonthUserDefaultsKey) as? [String: String] {
            let currentMonthKey = formattedMonth(for: currentDate)
            self.totalHours = monthlyHours[currentMonthKey] ?? ""
        } else {
            self.totalHours = ""
        }
        totalHoursLabel.text = totalHours
    }
    
    func shouldDisplayLayover(for date: Date) -> Bool {
        var allSchedules: [[String: String]] = []
        for (_, scheduleArray) in schedules {
            for schedule in scheduleArray {
                allSchedules.append(schedule)
            }
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-MMM-yyyy"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        allSchedules.sort { (s1, s2) -> Bool in
            let dep1 = dateFormatter.date(from: s1["DepDate"] ?? "") ?? Date.distantPast
            let dep2 = dateFormatter.date(from: s2["DepDate"] ?? "") ?? Date.distantPast
            return dep1 < dep2
        }
        for (index, schedule) in allSchedules.enumerated() {
            if let hotel = schedule["Hotel"], !hotel.isEmpty,
               let arrDateStr = schedule["ArrDate"],
               let arrDate = dateFormatter.date(from: arrDateStr) {
                guard let layoverStart = calendar.date(byAdding: .day, value: 1, to: arrDate) else { continue }
                var layoverEnd: Date?
                if index < allSchedules.count - 1 {
                    if let nextDepStr = allSchedules[index + 1]["DepDate"],
                       let nextDep = dateFormatter.date(from: nextDepStr),
                       let end = calendar.date(byAdding: .day, value: -1, to: nextDep) {
                        layoverEnd = end
                    }
                }
                if date >= layoverStart && (layoverEnd == nil || date <= layoverEnd!) {
                    return true
                }
            }
        }
        return false
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return 49
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "dayCell", for: indexPath) as! CalendarDayCell
        let isLandscape = view.bounds.width > view.bounds.height
        let isiPhone = UIDevice.current.userInterfaceIdiom == .phone
        
        if indexPath.item < 7 {
            cell.isHeader = true
            cell.dateLabel.text = daysOfWeek[indexPath.item]
            cell.dateLabel.font = UIFont.boldSystemFont(ofSize: (isiPhone && isLandscape) ? 6 : 10)
            cell.dateLabel.textColor = .black // 헤더 셀은 항상 검정색
            cell.scheduleStackView.isHidden = true
            cell.contentView.backgroundColor = .clear // 헤더 배경은 clear 처리
        } else {
            cell.isHeader = false
            let components = calendar.dateComponents([.year, .month], from: currentDate)
            guard let firstDayOfMonth = calendar.date(from: components) else { return cell }
            let weekday = calendar.component(.weekday, from: firstDayOfMonth)
            var offset = weekday - calendar.firstWeekday
            if offset < 0 { offset += 7 }
            let index = indexPath.item - 7
            let dayNumber = index - offset + 1
            let currentMonthRange = calendar.range(of: .day, in: .month, for: currentDate)!
            let currentMonthDays = currentMonthRange.count
            var displayDate: Date?
            var textColor: UIColor = .black
            
            if dayNumber < 1 {
                if let previousMonth = calendar.date(byAdding: .month, value: -1, to: currentDate),
                   let previousMonthRange = calendar.range(of: .day, in: .month, for: previousMonth) {
                    let previousMonthDays = previousMonthRange.count
                    let day = previousMonthDays + dayNumber
                    cell.contentView.backgroundColor = UIColor(named: "LightGreen")
                    textColor = UIColor(named: "DarkGreen") ?? .green
                    var prevComponents = calendar.dateComponents([.year, .month], from: previousMonth)
                    prevComponents.day = day
                    displayDate = calendar.date(from: prevComponents)
                }
            } else if dayNumber > currentMonthDays {
                let day = dayNumber - currentMonthDays
                cell.contentView.backgroundColor = UIColor(named: "LightGreen")
                textColor = UIColor(named: "DarkGreen") ?? .green
                if let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentDate) {
                    var nextComponents = calendar.dateComponents([.year, .month], from: nextMonth)
                    nextComponents.day = day
                    displayDate = calendar.date(from: nextComponents)
                }
            } else {
                cell.contentView.backgroundColor = .white
                textColor = .black
                var currentComponents = calendar.dateComponents([.year, .month], from: currentDate)
                currentComponents.day = dayNumber
                displayDate = calendar.date(from: currentComponents)
            }
            
            let dateText = ""
            // 날짜 셀 구성 부분 (cellForItemAt 내부)
            if let validDisplayDate = displayDate {
                let dateFormatter = DateFormatter()
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                dateFormatter.dateFormat = "MMM dd"
                let dateText = dateFormatter.string(from: validDisplayDate)
                
                let dateFontSize: CGFloat = (isiPhone && isLandscape) ? 7 : 10
                
                // 오늘 날짜인 경우: 빨간색 둥근 사각형 배경, 하얀색 볼드 글씨로 처리
                if Calendar.current.isDate(validDisplayDate, inSameDayAs: Date()) {
                    cell.dateLabel.text = dateText
                    cell.dateLabel.font = UIFont.boldSystemFont(ofSize: dateFontSize)
                    cell.dateLabel.textColor = .white
                    cell.dateLabel.backgroundColor = .red
                    cell.dateLabel.textAlignment = .center
                    cell.dateLabel.clipsToBounds = true
                    cell.dateLabel.layer.cornerRadius = 4  // 필요에 따라 조정 가능
                } else {
                    cell.dateLabel.text = dateText
                    cell.dateLabel.font = UIFont.boldSystemFont(ofSize: dateFontSize)
                    cell.dateLabel.textColor = textColor
                    cell.dateLabel.backgroundColor = .clear
                }
            } else {
                cell.dateLabel.text = "LAYOVER"
            }

            
            cell.scheduleStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
            
            var scheduleTextColor: UIColor = textColor
            if let validDisplayDate = displayDate {
                // UTC DateFormatter (휴일 키용)
                let utcFormatter = DateFormatter()
                utcFormatter.locale = Locale(identifier: "en_US_POSIX")
                utcFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                utcFormatter.dateFormat = "yyyy-MM-dd"

                // 현지 validDisplayDate를 UTC 기준으로 보정
                let utcCalendar = Calendar(identifier: .gregorian)
                var utcComponents = utcCalendar.dateComponents([.year, .month, .day], from: validDisplayDate)
                utcComponents.timeZone = TimeZone(secondsFromGMT: 0)
                if let normalizedDate = utcCalendar.date(from: utcComponents) {
                    // UTC 기준 날짜 문자열 생성 (dateText도 이 normalizedDate를 기반으로)
                    let dateTextFormatter = DateFormatter()
                    dateTextFormatter.locale = Locale(identifier: "en_US_POSIX")
                    dateTextFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                    dateTextFormatter.dateFormat = "MMM dd" // 원하는 형식으로 변경 가능
                    let normalizedDateText = dateTextFormatter.string(from: normalizedDate)
                    
                    let holidayKey = utcFormatter.string(from: normalizedDate)
                    if let holiday = holidays[holidayKey] {
                        cell.dateLabel.text = normalizedDateText + " [\(holiday)]"
                        cell.contentView.backgroundColor = UIColor(named: "LightYellow")
                        cell.dateLabel.textColor = UIColor(named: "DarkYellow") ?? .yellow
                        scheduleTextColor = UIColor(named: "DarkYellow") ?? .yellow
                    }
                }
                
                let scheduleDateFormatter = DateFormatter()
                scheduleDateFormatter.locale = Locale(identifier: "en_US_POSIX")
                scheduleDateFormatter.dateFormat = "dd-MMM-yyyy"
                
                var schedulesForCell: [[String: String]] = []
                for (_, scheduleArray) in schedules {
                    for schedule in scheduleArray {
                        if let depDateStr = schedule["DepDate"],
                           let arrDateStr = (schedule["ArrDate"] ?? schedule["DutyDebriefDate"]),
                           let depDate = scheduleDateFormatter.date(from: depDateStr),
                           let arrDate = scheduleDateFormatter.date(from: arrDateStr) {
                            if depDate > arrDate {
                                if calendar.isDate(validDisplayDate, inSameDayAs: depDate) ||
                                   calendar.isDate(validDisplayDate, inSameDayAs: arrDate) {
                                    schedulesForCell.append(schedule)
                                }
                            } else {
                                if validDisplayDate >= depDate && validDisplayDate <= arrDate {
                                    schedulesForCell.append(schedule)
                                }
                            }
                        } else if let depDateStr = schedule["DepDate"],
                                  let depDate = scheduleDateFormatter.date(from: depDateStr) {
                            if calendar.isDate(validDisplayDate, inSameDayAs: depDate) {
                                schedulesForCell.append(schedule)
                            }
                        }
                    }
                }
                
                schedulesForCell.sort { (s1, s2) -> Bool in
                    let depDate1 = scheduleDateFormatter.date(from: s1["DepDate"] ?? "") ?? Date.distantPast
                    let depDate2 = scheduleDateFormatter.date(from: s2["DepDate"] ?? "") ?? Date.distantPast
                    return depDate1 < depDate2
                }
                
                let scheduleFontSize: CGFloat = (isiPhone && isLandscape) ? 5 : 8
                
                // SDC 값이 있는 경우, 첫 번째 SDC 값만 날짜 셀 바로 아래에 표시
                if let firstScheduleWithSDC = schedulesForCell.first(where: { schedule in
                    if let sdc = schedule["SDC"], !sdc.isEmpty { return true }
                    return false
                }), let sdcValue = firstScheduleWithSDC["SDC"] {
                    let sdcLabel = UILabel()
                    sdcLabel.font = UIFont.boldSystemFont(ofSize: scheduleFontSize)
                    sdcLabel.textAlignment = .left
                    sdcLabel.textColor = scheduleTextColor
                    sdcLabel.numberOfLines = 0
                    sdcLabel.text = "🛑 [\(sdcValue)]"
                    cell.scheduleStackView.addArrangedSubview(sdcLabel)
                }
                
                // 각 스케줄 레이블 생성 (SDC 값은 위에서 한 번만 표시)
                for schedule in schedulesForCell {
                    let scheduleLabel = UILabel()
                    scheduleLabel.font = UIFont.boldSystemFont(ofSize: scheduleFontSize)
                    scheduleLabel.textAlignment = .left
                    scheduleLabel.textColor = scheduleTextColor
                    scheduleLabel.numberOfLines = 0
                    
                    var scheduleText = ""
                    
                    if let workType = schedule["WorkType"], workType == "FLY" || workType == "TVL" {
                        var item = schedule["Item"] ?? ""
                        if workType == "TVL" {
                            if item.count >= 2 {
                                item = "DH" + item.dropFirst(2)
                            } else {
                                item = "DH"
                            }
                        }
                        
                        let depTime = schedule["DepStnTime"] ?? ""
                        let depAp = schedule["DepAp"] ?? ""
                        let arrAp = schedule["ArrAp"] ?? ""
                        let arrTime = schedule["ArrStnTime"] ?? ""
                        
                        guard let depDateStr = schedule["DepDate"],
                              let arrDateStr = (schedule["ArrDate"] ?? schedule["DutyDebriefDate"]),
                              let depDate = scheduleDateFormatter.date(from: depDateStr),
                              let arrDate = scheduleDateFormatter.date(from: arrDateStr) else { continue }

                        let isOvernight = !calendar.isDate(depDate, inSameDayAs: arrDate)
                        if isOvernight {
                            if calendar.isDate(validDisplayDate, inSameDayAs: depDate) {
                                scheduleText = "\(item) \(depTime) \(depAp) - \(arrAp) 23:59"
                            } else if calendar.isDate(validDisplayDate, inSameDayAs: arrDate) {
                                scheduleText = "\(item) 00:00 \(depAp) - \(arrAp) \(arrTime)"
                            } else {
                                continue
                            }
                        } else {
                            scheduleText = "\(item) \(depTime) \(depAp) - \(arrAp) \(arrTime)"
                        }
                    } else {
                        let activity = schedule["Activity"] ?? ""
                        let dutyReport = schedule["DutyReport"] ?? ""
                        let rawDutyDebrief = schedule["DutyDebrief"] ?? "N/A"
                        let pureDutyDebrief = rawDutyDebrief.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? rawDutyDebrief
                        
                        let depDateStr = schedule["DepDate"] ?? ""
                        let dutyDebriefDateStr = schedule["DutyDebriefDate"] ?? ""
                        
                        if let depDateObj = scheduleDateFormatter.date(from: depDateStr),
                           let dutyDebriefDateObj = scheduleDateFormatter.date(from: dutyDebriefDateStr) {
                            if !calendar.isDate(depDateObj, inSameDayAs: dutyDebriefDateObj) {
                                if calendar.isDate(validDisplayDate, inSameDayAs: depDateObj) {
                                    scheduleText = "\(activity) \(dutyReport) - 23:59"
                                } else if calendar.isDate(validDisplayDate, inSameDayAs: dutyDebriefDateObj) {
                                    scheduleText = "\(activity) 00:00 - \(pureDutyDebrief)"
                                } else {
                                    continue
                                }
                            } else {
                                scheduleText = "\(activity) \(dutyReport) - \(pureDutyDebrief)"
                            }
                        } else {
                            scheduleText = "\(activity) \(dutyReport) - \(pureDutyDebrief)"
                        }
                    }
                    // SDC 값은 이미 위에서 한 번만 표시했으므로 여기서는 포함하지 않음.
                    scheduleLabel.text = scheduleText
                    cell.scheduleStackView.addArrangedSubview(scheduleLabel)
                }
                
                if schedulesForCell.isEmpty, let validDisplayDate = displayDate, self.shouldDisplayLayover(for: validDisplayDate) {
                    let layoverLabel = UILabel()
                    layoverLabel.font = UIFont.boldSystemFont(ofSize: (isiPhone && isLandscape) ? 5 : 8)
                    layoverLabel.textAlignment = .left
                    layoverLabel.textColor = scheduleTextColor
                    layoverLabel.text = "LAYOVER"
                    cell.scheduleStackView.addArrangedSubview(layoverLabel)
                }
            }
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let flowLayout = collectionViewLayout as? UICollectionViewFlowLayout else {
            return CGSize.zero
        }
        let sectionInset = flowLayout.sectionInset
        let interItemSpacing = flowLayout.minimumInteritemSpacing
        let totalHorizontalSpacing = sectionInset.left + sectionInset.right + interItemSpacing * 6
        let cellWidth = floor((collectionView.frame.width - totalHorizontalSpacing) / 7)
        let isLandscape = view.bounds.width > view.bounds.height
        let isiPhone = UIDevice.current.userInterfaceIdiom == .phone
        let headerRowHeight: CGFloat = (isiPhone && isLandscape) ? 20 : 30
        
        if indexPath.item < 7 {
            return CGSize(width: cellWidth, height: headerRowHeight)
        } else {
            let lineSpacing = flowLayout.minimumLineSpacing
            let totalVerticalSpacing = flowLayout.sectionInset.top + flowLayout.sectionInset.bottom + headerRowHeight + lineSpacing * 5
            let availableHeight = collectionView.frame.height - totalVerticalSpacing
            let cellHeight = availableHeight / 6
            return CGSize(width: cellWidth, height: cellHeight)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item >= 7 else { return }
        let components = calendar.dateComponents([.year, .month], from: currentDate)
        guard let firstDayOfMonth = calendar.date(from: components) else { return }
        let weekday = calendar.component(.weekday, from: firstDayOfMonth)
        var offset = weekday - calendar.firstWeekday
        if offset < 0 { offset += 7 }
        let index = indexPath.item - 7
        let dayNumber = index - offset + 1
        
        var displayDate: Date?
        if dayNumber < 1 {
            if let previousMonth = calendar.date(byAdding: .month, value: -1, to: currentDate),
               let previousMonthRange = calendar.range(of: .day, in: .month, for: previousMonth) {
                let day = previousMonthRange.count + dayNumber
                var prevComponents = calendar.dateComponents([.year, .month], from: previousMonth)
                prevComponents.day = day
                displayDate = calendar.date(from: prevComponents)
            }
        } else if dayNumber > calendar.range(of: .day, in: .month, for: currentDate)!.count {
            let day = dayNumber - calendar.range(of: .day, in: .month, for: currentDate)!.count
            if let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentDate) {
                var nextComponents = calendar.dateComponents([.year, .month], from: nextMonth)
                nextComponents.day = day
                displayDate = calendar.date(from: nextComponents)
            }
        } else {
            var currentComponents = calendar.dateComponents([.year, .month], from: currentDate)
            currentComponents.day = dayNumber
            displayDate = calendar.date(from: currentComponents)
        }
        
        guard let selectedDate = displayDate else { return }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MMM-yyyy"
        let selectedDateString = formatter.string(from: selectedDate)
        
        var filteredSchedules = [[String: String]]()
        for (_, scheduleArray) in schedules {
            for schedule in scheduleArray {
                if let depDate = schedule["DepDate"], depDate == selectedDateString {
                    filteredSchedules.append(schedule)
                } else if let arrDate = schedule["ArrDate"], arrDate == selectedDateString {
                    filteredSchedules.append(schedule)
                }
            }
        }
        
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let detailVC = storyboard.instantiateViewController(withIdentifier: "ScheduleDetailViewController") as? ScheduleDetailViewController {
            detailVC.selectedDate = selectedDateString
            detailVC.scheduleDetailsList = filteredSchedules
            detailVC.modalPresentationStyle = .formSheet
            present(detailVC, animated: true, completion: nil)
        }
    }
}

// MARK: - CalendarDayCell: 달력의 각 셀 커스텀 클래스
class CalendarDayCell: UICollectionViewCell {
    let dateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let scheduleStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 2
        stackView.alignment = .leading
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    var isHeader: Bool = false {
        didSet {
            updateLayoutForHeader()
        }
    }
    
    private var headerConstraints: [NSLayoutConstraint] = []
    private var normalConstraints: [NSLayoutConstraint] = []
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        // 셀 테두리 설정
        contentView.layer.borderWidth = 0.5
        contentView.layer.borderColor = UIColor(named: "Ocean")?.cgColor
        
        contentView.addSubview(dateLabel)
        contentView.addSubview(scheduleStackView)
        setupNormalConstraints()
        setupHeaderConstraints()
        updateLayoutForHeader()
    }
    
    // 일반 셀의 제약조건 설정
    private func setupNormalConstraints() {
        normalConstraints = [
            dateLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            dateLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            scheduleStackView.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 2),
            scheduleStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            scheduleStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            scheduleStackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -2)
        ]
    }
    
    // 헤더 셀의 제약조건 설정
    private func setupHeaderConstraints() {
        headerConstraints = [
            dateLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            dateLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ]
    }
    
    // 헤더 여부에 따라 레이아웃 업데이트
    private func updateLayoutForHeader() {
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
        setNeedsLayout()
    }
    
    // 셀 재사용 시 스타일 초기화
    override func prepareForReuse() {
        super.prepareForReuse()
        // 기본 배경색 및 텍스트 색상으로 초기화
        contentView.backgroundColor = .clear
        dateLabel.backgroundColor = .clear
        dateLabel.textColor = .black
        scheduleStackView.isHidden = false
        // 필요 시 isHeader 값을 초기화(헤더 셀은 collectionView의 cellForItemAt에서 명시적으로 설정됨)
        isHeader = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
