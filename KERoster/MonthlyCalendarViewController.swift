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
    
    // monthLabel: "MMMM yyyy" 형식의 월 표시 (동적 폰트 적용)
    let monthLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.scaledBoldFont(ofSize: 20)
        label.textAlignment = .center
        label.textColor = .black  // 월 표시 글자색은 기본 검정
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
    
    // 요일 배열
    let daysOfWeek = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    
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
        updateMonthLabel()
        fetchHolidays(for: currentDate)
        
       
        // 콘솔에 원본(가공되지 않은) 해당월 schedules 데이터 출력
        print (schedules)
        printRawSchedulesForCurrentMonth()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.collectionViewLayout.invalidateLayout()
    }
    
    // MARK: - Auto Layout 제약조건 설정
    func setupConstraints() {
        NSLayoutConstraint.activate([
            // 상단 컨트롤 뷰
            monthControlView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            monthControlView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            monthControlView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            monthControlView.heightAnchor.constraint(equalToConstant: 40),
            
            // 이전 버튼
            prevButton.leadingAnchor.constraint(equalTo: monthControlView.leadingAnchor),
            prevButton.centerYAnchor.constraint(equalTo: monthControlView.centerYAnchor),
            prevButton.widthAnchor.constraint(equalToConstant: 80),
            
            // 다음 버튼
            nextButton.trailingAnchor.constraint(equalTo: monthControlView.trailingAnchor),
            nextButton.centerYAnchor.constraint(equalTo: monthControlView.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 80),
            
            // 월 레이블
            monthLabel.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: 10),
            monthLabel.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -10),
            monthLabel.centerYAnchor.constraint(equalTo: monthControlView.centerYAnchor),
            
            // 컬렉션 뷰
            collectionView.topAnchor.constraint(equalTo: monthControlView.bottomAnchor, constant: 10),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
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
    
    // UICollectionViewDataSource
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return 49
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "dayCell", for: indexPath) as! CalendarDayCell
        
        if indexPath.item < 7 {
            cell.isHeader = true
            cell.dateLabel.text = daysOfWeek[indexPath.item]
            cell.dateLabel.font = UIFont.boldSystemFont(ofSize: 12)
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
            cell.dateLabel.font = UIFont.boldSystemFont(ofSize: 10)
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
                                // 오버나이트 스케줄
                                if calendar.isDate(displayDate, inSameDayAs: depDate) ||
                                   calendar.isDate(displayDate, inSameDayAs: arrDate) {
                                    schedulesForCell.append(schedule)
                                }
                            } else {
                                // 일반 스케줄
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
                
                // 각 스케줄을 처리하면서 콘솔에 출력 및 셀에 추가
                for schedule in schedulesForCell {
                    let scheduleLabel = UILabel()
                    scheduleLabel.font = UIFont.boldSystemFont(ofSize: 9)
                    scheduleLabel.textAlignment = .left
                    scheduleLabel.textColor = scheduleTextColor
                    scheduleLabel.numberOfLines = 0
                    
                    var scheduleText = ""
                    
                    if let workType = schedule["WorkType"], workType == "FLY" || workType == "TVL" {
                        // FLY / TVL 스케줄 처리
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
                            // 오버나이트 스케줄: 출발일과 도착일 각각 별도 처리
                            if calendar.isDate(displayDate, inSameDayAs: depDate) {
                                scheduleText = "\(item) \(depTime) \(depAp) - \(arrAp) 23:59"
                            } else if calendar.isDate(displayDate, inSameDayAs: arrDate) {
                                scheduleText = "\(item) 00:00 \(depAp) - \(arrAp) \(arrTime)"
                            } else {
                                continue
                            }
                        } else {
                            // 일반 스케줄: DepDate와 ArrDate 사이의 날짜에 모두 포함시키는 경우
                            if cellDateString == depDateStr {
                                scheduleText = "\(item) \(depTime) \(depAp) - \(arrAp) 23:59"
                            } else if cellDateString == arrDateStr {
                                scheduleText = "\(item) 00:00 \(depAp) - \(arrAp) \(arrTime)"
                            } else {
                                // 만약 DepDate와 ArrDate가 같은 경우 또는 중간 날짜의 경우 기본 포맷 적용
                                scheduleText = "\(item) \(depTime) \(depAp) - \(arrAp) \(arrTime)"
                            }
                        }
                    } else {
                        // non‑FLY/TVL 스케줄 처리
                        let activity = schedule["Activity"] ?? ""
                        let dutyReport = schedule["DutyReport"] ?? ""
                        let dutyDebriefTime = schedule["DutyDebrief"] ?? ""
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
                    
                    // 콘솔에 해당 셀과 스케줄 내용을 출력
                    print("Cell [\(dateText)] schedule: \(scheduleText)")
                    
                    scheduleLabel.text = scheduleText
                    cell.scheduleStackView.addArrangedSubview(scheduleLabel)
                }
                
                // 스케줄이 없는 날짜 셀의 경우, 호텔 스케줄에 따른 LAYOVER 여부 확인 (여기서는 기존 방식 유지)
                if schedulesForCell.isEmpty {
                    if shouldDisplayLayover(for: displayDate) {
                        let layoverLabel = UILabel()
                        layoverLabel.font = UIFont.boldSystemFont(ofSize: 9)
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
    
    // UICollectionViewDelegateFlowLayout: 셀 크기 설정
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let flowLayout = collectionViewLayout as? UICollectionViewFlowLayout else {
            return CGSize.zero
        }
        let sectionInset = flowLayout.sectionInset
        let interItemSpacing = flowLayout.minimumInteritemSpacing
        let totalHorizontalSpacing = sectionInset.left + sectionInset.right + interItemSpacing * 6
        let cellWidth = (collectionView.frame.width - totalHorizontalSpacing) / 7
        
        let headerRowHeight: CGFloat = 30
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
