//
//  MonthlyCalendarViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/02/04.
//

import UIKit

// MARK: - 폰트 동적 스케일링을 위한 UIFont Extension
extension UIFont {
    /// 기준 너비(834포인트, iPad Pro 11인치 기준)에 따른 스케일 팩터를 적용한 Bold 폰트를 반환
    static func scaledBoldFont(ofSize size: CGFloat) -> UIFont {
        let baseWidth: CGFloat = 834.0 // 기준 너비 (iPad Pro 11인치)
        let screenWidth = UIScreen.main.bounds.width
        let scaleFactor = screenWidth / baseWidth
        return UIFont.boldSystemFont(ofSize: size * scaleFactor)
    }
    
    /// 기준 너비(834포인트, iPad Pro 11인치 기준)에 따른 스케일 팩터를 적용한 일반 시스템 폰트를 반환
    static func scaledSystemFont(ofSize size: CGFloat) -> UIFont {
        let baseWidth: CGFloat = 834.0
        let screenWidth = UIScreen.main.bounds.width
        let scaleFactor = screenWidth / baseWidth
        return UIFont.systemFont(ofSize: size * scaleFactor)
    }
}

class MonthlyCalendarViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    // 스케줄 데이터:
    // 각 스케줄 항목은 "dd-MMM-yyyy" 형식의 DepDate, ArrDate, DutyDebriefDate 등 여러 정보를 포함함.
    var schedules: [String: [[String: String]]] = [:]
    
    // 날짜별 휴일 정보를 저장 (키: "yyyy-MM-dd")
    var holidays: [String: String] = [:]
    
    // 현재 보여지는 날짜 (월 단위)
    var currentDate = Date()
    
    // 현재 사용 중인 Calendar 객체
    let calendar = Calendar.current
    
    // 상단 컨트롤 뷰 (배경색 삭제)
    let monthControlView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // 이전 버튼: SF Symbol "arrowshape.backward.circle.fill" 사용, 채우기 색상은 "Ocean"
    let prevButton: UIButton = {
        let button = UIButton(type: .system)
        if let image = UIImage(systemName: "arrowshape.backward.circle.fill")?.withRenderingMode(.alwaysTemplate) {
            button.setImage(image, for: .normal)
        }
        button.tintColor = UIColor(named: "Ocean")
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // 다음 버튼: SF Symbol "arrowshape.forward.circle.fill" 사용, 채우기 색상은 "Ocean"
    let nextButton: UIButton = {
        let button = UIButton(type: .system)
        if let image = UIImage(systemName: "arrowshape.forward.circle.fill")?.withRenderingMode(.alwaysTemplate) {
            button.setImage(image, for: .normal)
        }
        button.tintColor = UIColor(named: "Ocean")
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // 월 레이블: "MMMM yyyy" 형식 (동적 폰트 적용)
    let monthLabel: UILabel = {
        let label = UILabel()
        // 기본 폰트는 세로 모드 기준 (나중에 updateLayoutForOrientation에서 변경)
        label.font = UIFont.scaledBoldFont(ofSize: 20)
        label.textAlignment = .center
        label.textColor = .black  // 기본 검정색
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // 달력 컬렉션 뷰
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
    
    // 요일 배열 (iPhone일 경우 축약형, 그 외의 기기는 풀네임)
    var daysOfWeek: [String] {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
        } else {
            return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        }
    }
    
    // MARK: - 레이아웃 제약 (인스턴스 변수)
    var monthControlHeightConstraint: NSLayoutConstraint!
    var collectionViewTopConstraint: NSLayoutConstraint!
    var prevButtonWidthConstraint: NSLayoutConstraint!
    var nextButtonWidthConstraint: NSLayoutConstraint!
    
    // MARK: - View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        navigationItem.title = "ROSTER SUMMARY"
        
        // 상단 컨트롤 뷰 및 하위 뷰 추가
        view.addSubview(monthControlView)
        monthControlView.addSubview(prevButton)
        monthControlView.addSubview(monthLabel)
        monthControlView.addSubview(nextButton)
        
        // 이전/다음 버튼 액션 설정
        prevButton.addTarget(self, action: #selector(prevMonth), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextMonth), for: .touchUpInside)
        
        // 컬렉션 뷰 설정 (delegate, dataSource)
        view.addSubview(collectionView)
        collectionView.delegate = self
        collectionView.dataSource = self
        
        setupConstraints()
        updateLayoutForOrientation(size: view.bounds.size)
        updateMonthLabel()
        fetchHolidays(for: currentDate)
        
        // 콘솔에 스케줄 데이터 출력 (필요시)
        //print(schedules)
        //printRawSchedulesForCurrentMonth()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.collectionViewLayout.invalidateLayout()
    }
    
    // 회전(방향 전환) 시 레이아웃 갱신
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.updateLayoutForOrientation(size: size)
            self.collectionView.collectionViewLayout.invalidateLayout()
            self.view.layoutIfNeeded()
        }, completion: nil)
    }
    
    // MARK: - Auto Layout 제약조건 설정
    func setupConstraints() {
        // monthControlView 높이 제약 (기본 40, 나중에 updateLayoutForOrientation에서 변경)
        monthControlHeightConstraint = monthControlView.heightAnchor.constraint(equalToConstant: 40)
        // collectionView 상단 제약 (기본 10)
        collectionViewTopConstraint = collectionView.topAnchor.constraint(equalTo: monthControlView.bottomAnchor, constant: 10)
        // 버튼 너비 제약 (기본 80)
        prevButtonWidthConstraint = prevButton.widthAnchor.constraint(equalToConstant: 80)
        nextButtonWidthConstraint = nextButton.widthAnchor.constraint(equalToConstant: 80)
        
        NSLayoutConstraint.activate([
            // 상단 컨트롤 뷰
            monthControlView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            monthControlView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            monthControlView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            monthControlHeightConstraint,
            
            // 이전 버튼
            prevButton.leadingAnchor.constraint(equalTo: monthControlView.leadingAnchor),
            prevButton.centerYAnchor.constraint(equalTo: monthControlView.centerYAnchor),
            prevButtonWidthConstraint,
            
            // 다음 버튼
            nextButton.trailingAnchor.constraint(equalTo: monthControlView.trailingAnchor),
            nextButton.centerYAnchor.constraint(equalTo: monthControlView.centerYAnchor),
            nextButtonWidthConstraint,
            
            // 월 레이블
            monthLabel.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: 10),
            monthLabel.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -10),
            monthLabel.centerYAnchor.constraint(equalTo: monthControlView.centerYAnchor),
            
            // 컬렉션 뷰
            collectionViewTopConstraint,
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    /// 기기 및 방향에 따라 상단 컨트롤 뷰, 컬렉션 뷰 간격, 버튼 너비, 그리고 월 레이블 폰트 크기를 조정
    func updateLayoutForOrientation(size: CGSize) {
        let isLandscape = size.width > size.height
        let isiPhone = UIDevice.current.userInterfaceIdiom == .phone
        
        if isiPhone && isLandscape {
            // iPhone 가로 모드일 경우
            monthControlHeightConstraint.constant = 20   // 컨트롤 뷰 높이 20
            collectionViewTopConstraint.constant = 2         // 컬렉션 뷰 상단 간격 2
            prevButtonWidthConstraint.constant = 40          // 버튼 너비 40
            nextButtonWidthConstraint.constant = 40
            // 월 레이블 폰트 조정 (예: 14 포인트)
            monthLabel.font = UIFont.scaledBoldFont(ofSize: 14)
        } else {
            // 그 외의 경우 (세로 모드 혹은 iPad)
            monthControlHeightConstraint.constant = 40
            collectionViewTopConstraint.constant = 10
            prevButtonWidthConstraint.constant = 80
            nextButtonWidthConstraint.constant = 80
            monthLabel.font = UIFont.scaledBoldFont(ofSize: 20)
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
        let urlString = "https://www.googleapis.com/calendar/v3/calendars/\(calendarId)/events?key=\(apiKey)&&orderBy=startTime&singleEvents=true&timeMin=\(timeMin)&timeMax=\(timeMax)"
        
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
    }
    
    @objc func nextMonth() {
        currentDate = calendar.date(byAdding: .month, value: 1, to: currentDate) ?? currentDate
        updateMonthLabel()
        fetchHolidays(for: currentDate)
        collectionView.reloadData()
    }
    
    // 헬퍼 함수: 호텔 스케줄 관련 (여기선 사용되지 않음)
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
        
        // DepDate 기준 오름차순 정렬
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
    
    // 콘솔에 원본(가공되지 않은) 해당월 schedules 데이터를 출력하는 함수
    func printRawSchedulesForCurrentMonth() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-MMM-yyyy"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        // 현재 달의 연, 월 정보
        let currentComponents = calendar.dateComponents([.year, .month], from: currentDate)
        
        for (key, scheduleArray) in schedules {
            for schedule in scheduleArray {
                if let depDateStr = schedule["DepDate"],
                   let depDate = dateFormatter.date(from: depDateStr) {
                    let scheduleComponents = calendar.dateComponents([.year, .month], from: depDate)
                    if scheduleComponents.year == currentComponents.year &&
                        scheduleComponents.month == currentComponents.month {
                        print("Raw Schedule [\(key)]: \(schedule)")
                    }
                }
            }
        }
    }
    
    // MARK: - UICollectionViewDataSource
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return 49
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "dayCell", for: indexPath) as! CalendarDayCell
        
        // 기기 및 방향 감지
        let isLandscape = view.bounds.width > view.bounds.height
        let isiPhone = UIDevice.current.userInterfaceIdiom == .phone
        
        if indexPath.item < 7 {
            cell.isHeader = true
            // 요일 헤더 텍스트는 daysOfWeek 배열에서 가져옴 (iPhone이면 축약, 그 외는 풀네임)
            cell.dateLabel.text = daysOfWeek[indexPath.item]
            // iPhone 가로 모드에서는 헤더 셀 폰트 크기를 6포인트, 그 외에는 10포인트
            let headerFontSize: CGFloat = (isiPhone && isLandscape) ? 6 : 10
            cell.dateLabel.font = UIFont.boldSystemFont(ofSize: headerFontSize)
            cell.dateLabel.textColor = .black
            cell.scheduleStackView.isHidden = true
            cell.contentView.backgroundColor = .clear
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
            
            var dateText = ""
            if let displayDate = displayDate {
                let dateFormatter = DateFormatter()
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                dateFormatter.dateFormat = "MMM dd"
                dateText = dateFormatter.string(from: displayDate)
                cell.dateLabel.text = dateText
            } else {
                cell.dateLabel.text = "LAYOVER"
            }
            // 날짜 라벨 폰트: iPhone 가로 모드에서는 7포인트, 그 외에는 10포인트
            let dateFontSize: CGFloat = (isiPhone && isLandscape) ? 7 : 10
            cell.dateLabel.font = UIFont.boldSystemFont(ofSize: dateFontSize)
            cell.dateLabel.textColor = textColor
            
            cell.scheduleStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
            
            var scheduleTextColor: UIColor = textColor
            if let displayDate = displayDate {
                let holidayFormatter = DateFormatter()
                holidayFormatter.locale = Locale(identifier: "en_US_POSIX")
                holidayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                holidayFormatter.dateFormat = "yyyy-MM-dd"
                if let nextDay = calendar.date(byAdding: .day, value: 1, to: displayDate) {
                    let holidayKey = holidayFormatter.string(from: nextDay)
                    if let holiday = holidays[holidayKey] {
                        cell.dateLabel.text = "[\(holiday)] " + dateText
                        cell.contentView.backgroundColor = UIColor(named: "LightYellow")
                        cell.dateLabel.textColor = UIColor(named: "DarkYellow") ?? .yellow
                        scheduleTextColor = UIColor(named: "DarkYellow") ?? .yellow
                    }
                }
                
                let scheduleDateFormatter = DateFormatter()
                scheduleDateFormatter.locale = Locale(identifier: "en_US_POSIX")
                scheduleDateFormatter.dateFormat = "dd-MMM-yyyy"
                
                var schedulesForCell: [[String: String]] = []
                // 스케줄 필터링: 오버나이트 스케줄은 DepDate와 ArrDate 각각 해당하는 셀에 추가
                for (_, scheduleArray) in schedules {
                    for schedule in scheduleArray {
                        if let depDateStr = schedule["DepDate"],
                           let arrDateStr = schedule["ArrDate"],
                           let depDate = scheduleDateFormatter.date(from: depDateStr),
                           let arrDate = scheduleDateFormatter.date(from: arrDateStr) {
                            
                            if depDate > arrDate {
                                if calendar.isDate(displayDate, inSameDayAs: depDate) ||
                                   calendar.isDate(displayDate, inSameDayAs: arrDate) {
                                    schedulesForCell.append(schedule)
                                }
                            } else {
                                if displayDate >= depDate && displayDate <= arrDate {
                                    schedulesForCell.append(schedule)
                                }
                            }
                        } else if let depDateStr = schedule["DepDate"],
                                  let depDate = scheduleDateFormatter.date(from: depDateStr) {
                            if calendar.isDate(displayDate, inSameDayAs: depDate) {
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
                
                // 스케줄 폰트: iPhone 가로 모드에서는 5포인트 (원래 4포인트에서 1포인트 올림), 그 외에는 8포인트
                let scheduleFontSize: CGFloat = (isiPhone && isLandscape) ? 5 : 8
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
                              let arrDateStr = schedule["ArrDate"],
                              let depDate = scheduleDateFormatter.date(from: depDateStr),
                              let arrDate = scheduleDateFormatter.date(from: arrDateStr) else { continue }
                        
                        let isOvernight = depDate > arrDate
                        let cellDateString = scheduleDateFormatter.string(from: displayDate)
                        
                        if isOvernight {
                            if calendar.isDate(displayDate, inSameDayAs: depDate) {
                                scheduleText = "\(item) \(depTime) \(depAp) - \(arrAp) 23:59"
                            } else if calendar.isDate(displayDate, inSameDayAs: arrDate) {
                                scheduleText = "\(item) 00:00 \(depAp) - \(arrAp) \(arrTime)"
                            } else {
                                continue
                            }
                        } else {
                            if cellDateString == depDateStr && depDateStr != arrDateStr {
                                scheduleText = "\(item) \(depTime) \(depAp) - \(arrAp) 23:59"
                            } else if cellDateString == arrDateStr && depDateStr != arrDateStr {
                                scheduleText = "\(item) 00:00 \(depAp) - \(arrAp) \(arrTime)"
                            } else {
                                scheduleText = "\(item) \(depTime) \(depAp) - \(arrAp) \(arrTime)"
                            }
                        }
                    } else {
                        let activity = schedule["Activity"] ?? ""
                        let dutyReport = schedule["DutyReport"] ?? ""
                        let dutyDebriefTime = schedule["DutyDebriefTime"] ?? ""
                        let depDateStr = schedule["DepDate"] ?? ""
                        let dutyDebriefDateStr = schedule["DutyDebriefDate"] ?? ""
                        
                        if let depDateObj = scheduleDateFormatter.date(from: depDateStr),
                           let dutyDebriefDateObj = scheduleDateFormatter.date(from: dutyDebriefDateStr) {
                            if !calendar.isDate(depDateObj, inSameDayAs: dutyDebriefDateObj) {
                                if calendar.isDate(displayDate, inSameDayAs: depDateObj) {
                                    scheduleText = "\(activity) \(dutyReport) - 23:59"
                                } else if calendar.isDate(displayDate, inSameDayAs: dutyDebriefDateObj) {
                                    scheduleText = "\(activity) 00:00 - \(dutyDebriefTime)"
                                } else {
                                    continue
                                }
                            } else {
                                scheduleText = "\(activity) \(dutyReport) - \(dutyDebriefTime)"
                            }
                        } else {
                            scheduleText = "\(activity) \(dutyReport) - \(dutyDebriefTime)"
                        }
                    }
                    
                    print("Cell [\(dateText)] schedule: \(scheduleText)")
                    
                    scheduleLabel.text = scheduleText
                    cell.scheduleStackView.addArrangedSubview(scheduleLabel)
                }
                
                if schedulesForCell.isEmpty {
                    if shouldDisplayLayover(for: displayDate) {
                        let layoverLabel = UILabel()
                        layoverLabel.font = UIFont.boldSystemFont(ofSize: scheduleFontSize)
                        layoverLabel.textAlignment = .left
                        layoverLabel.textColor = scheduleTextColor
                        layoverLabel.text = "LAYOVER"
                        cell.scheduleStackView.addArrangedSubview(layoverLabel)
                    }
                }
            }
        }
        return cell
    }
    
    // MARK: - UICollectionViewDelegateFlowLayout: 셀 크기 설정
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let flowLayout = collectionViewLayout as? UICollectionViewFlowLayout else {
            return CGSize.zero
        }
        let sectionInset = flowLayout.sectionInset
        let interItemSpacing = flowLayout.minimumInteritemSpacing
        // 좌우 인셋 + 셀 사이 간격 (7열이면 간격은 6개)
        let totalHorizontalSpacing = sectionInset.left + sectionInset.right + interItemSpacing * 6
        let cellWidth = floor((collectionView.frame.width - totalHorizontalSpacing) / 7)
        
        let isLandscape = view.bounds.width > view.bounds.height
        let isiPhone = UIDevice.current.userInterfaceIdiom == .phone
        
        // iPhone 가로 모드에서는 헤더 높이를 20, 그 외는 30
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
        contentView.layer.borderWidth = 0.5
        contentView.layer.borderColor = UIColor(named: "Ocean")?.cgColor
        
        contentView.addSubview(dateLabel)
        contentView.addSubview(scheduleStackView)
        
        setupNormalConstraints()
        setupHeaderConstraints()
        updateLayoutForHeader()
    }
    
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
    
    private func setupHeaderConstraints() {
        headerConstraints = [
            dateLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            dateLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ]
    }
    
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
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
