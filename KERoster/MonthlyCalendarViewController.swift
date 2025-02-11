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

class MonthlyCalendarViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    var schedules: [String: [[String: String]]] = [:]
    let schedulesUserDefaultsKey = "schedules"
    var holidays: [String: String] = [:]
    var currentDate = Date()
    let calendar = Calendar.current
    
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
    
    var daysOfWeek: [String] {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
        } else {
            return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        }
    }
    
    var monthControlHeightConstraint: NSLayoutConstraint!
    var collectionViewTopConstraint: NSLayoutConstraint!
    var prevButtonWidthConstraint: NSLayoutConstraint!
    var nextButtonWidthConstraint: NSLayoutConstraint!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        navigationItem.title = "ROSTER SUMMARY"
        
        if schedules.isEmpty {
            loadSchedules()
        }
        
        view.addSubview(monthControlView)
        monthControlView.addSubview(prevButton)
        monthControlView.addSubview(monthLabel)
        monthControlView.addSubview(nextButton)
        
        prevButton.addTarget(self, action: #selector(prevMonth), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextMonth), for: .touchUpInside)
        
        view.addSubview(collectionView)
        collectionView.delegate = self
        collectionView.dataSource = self
        
        setupConstraints()
        updateLayoutForOrientation(size: view.bounds.size)
        updateMonthLabel()
        fetchHolidays(for: currentDate)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadSchedules()
        collectionView.reloadData()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 뷰의 압축된 콘텐츠 크기에 맞게 preferredContentSize를 업데이트합니다.
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
    
    func loadSchedules() {
        if let data = UserDefaults.standard.data(forKey: schedulesUserDefaultsKey) {
            do {
                schedules = try JSONDecoder().decode([String: [[String: String]]].self, from: data)
                print("스케줄 데이터 로드 성공")
            } catch {
                print("스케줄 불러오기 실패: \(error)")
            }
        } else {
            print("저장된 스케줄이 없습니다.")
        }
    }
    
    func setupConstraints() {
        monthControlHeightConstraint = monthControlView.heightAnchor.constraint(equalToConstant: 40)
        collectionViewTopConstraint = collectionView.topAnchor.constraint(equalTo: monthControlView.bottomAnchor, constant: 10)
        prevButtonWidthConstraint = prevButton.widthAnchor.constraint(equalToConstant: 80)
        nextButtonWidthConstraint = nextButton.widthAnchor.constraint(equalToConstant: 80)
        
        NSLayoutConstraint.activate([
            monthControlView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            monthControlView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            monthControlView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            monthControlHeightConstraint,
            prevButton.leadingAnchor.constraint(equalTo: monthControlView.leadingAnchor),
            prevButton.centerYAnchor.constraint(equalTo: monthControlView.centerYAnchor),
            prevButtonWidthConstraint,
            nextButton.trailingAnchor.constraint(equalTo: monthControlView.trailingAnchor),
            nextButton.centerYAnchor.constraint(equalTo: monthControlView.centerYAnchor),
            nextButtonWidthConstraint,
            monthLabel.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: 10),
            monthLabel.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -10),
            monthLabel.centerYAnchor.constraint(equalTo: monthControlView.centerYAnchor),
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
            prevButtonWidthConstraint.constant = 40
            nextButtonWidthConstraint.constant = 40
            monthLabel.font = UIFont.scaledBoldFont(ofSize: 14)
        } else {
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
    }
    
    @objc func nextMonth() {
        currentDate = calendar.date(byAdding: .month, value: 1, to: currentDate) ?? currentDate
        updateMonthLabel()
        fetchHolidays(for: currentDate)
        collectionView.reloadData()
    }
    
    // MARK: - 헬퍼 함수: 오버나이트(레이오버) 스케줄 관련
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
    
    // MARK: - UICollectionViewDataSource
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
            if let validDisplayDate = displayDate {
                let dateFormatter = DateFormatter()
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                dateFormatter.dateFormat = "MMM dd"
                dateText = dateFormatter.string(from: validDisplayDate)
                cell.dateLabel.text = dateText
            } else {
                cell.dateLabel.text = "LAYOVER"
            }
            let dateFontSize: CGFloat = (isiPhone && isLandscape) ? 7 : 10
            cell.dateLabel.font = UIFont.boldSystemFont(ofSize: dateFontSize)
            cell.dateLabel.textColor = textColor
            
            cell.scheduleStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
            
            var scheduleTextColor: UIColor = textColor
            if let validDisplayDate = displayDate {
                let holidayFormatter = DateFormatter()
                holidayFormatter.locale = Locale(identifier: "en_US_POSIX")
                holidayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                holidayFormatter.dateFormat = "yyyy-MM-dd"
                if let nextDay = calendar.date(byAdding: .day, value: 1, to: validDisplayDate) {
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
                for (_, scheduleArray) in schedules {
                    for schedule in scheduleArray {
                        if let depDateStr = schedule["DepDate"],
                           let arrDateStr = schedule["ArrDate"],
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
                        let cellDateString = scheduleDateFormatter.string(from: validDisplayDate)
                        
                        if isOvernight {
                            if calendar.isDate(validDisplayDate, inSameDayAs: depDate) {
                                scheduleText = "\(item) \(depTime) \(depAp) - \(arrAp) 23:59"
                            } else if calendar.isDate(validDisplayDate, inSameDayAs: arrDate) {
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
                                if calendar.isDate(validDisplayDate, inSameDayAs: depDateObj) {
                                    scheduleText = "\(activity) \(dutyReport) - 23:59"
                                } else if calendar.isDate(validDisplayDate, inSameDayAs: dutyDebriefDateObj) {
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
                    // 셀 확인 용
                    //print("Cell [\(dateText)] schedule: \(scheduleText)")
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
    
    // MARK: - UICollectionViewDelegateFlowLayout: 셀 크기 설정
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
    
    // MARK: - 셀 선택 시 해당 날짜 세부 정보를 모달 팝업으로 표시
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
                let previousMonthDays = previousMonthRange.count
                let day = previousMonthDays + dayNumber
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
        
        guard let selectedDateObj = displayDate else { return }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-MMM-yyyy"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let selectedDateString = dateFormatter.string(from: selectedDateObj)
        let filteredSchedules = schedules[selectedDateString] ?? []
        let detailVC = ScheduleDetailViewController()
        detailVC.scheduleDetailsList = filteredSchedules
        detailVC.selectedDate = selectedDateString
        detailVC.modalPresentationStyle = .formSheet
        present(detailVC, animated: true, completion: nil)
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
