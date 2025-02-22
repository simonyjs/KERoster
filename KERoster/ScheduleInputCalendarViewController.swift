//
//  ScheduleInputCalendarViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/02/12.
//

import UIKit

class ScheduleInputCalendarViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    // 현재 보여질 달의 날짜
    var currentDate = Date()
    let calendar = Calendar.current

    // 휴일 정보를 저장할 딕셔너리 (키: "yyyy-MM-dd" 문자열, API에서 받은 그대로)
    var holidays: [String: String] = [:]

    // 저장된 스케줄 데이터 (날짜 키: "dd-MMM-yyyy")
    var schedules: [String: [[String: String]]] = [:]

    // UserDefaults에 저장할 때 사용할 키 (imported schedules는 "schedules", 수동 입력 스케줄은 "manualSchedules")
    let schedulesUserDefaultsKey = "schedules"

    // MARK: - UI Elements

    // 상단 달 컨트롤 뷰 (월 이동 버튼, 월 라벨)
    let monthControlView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.clear
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
        label.textColor = UIColor.black
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

    // 달력 CollectionView
    let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 1
        layout.minimumInteritemSpacing = 1
        layout.sectionInset = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        layout.scrollDirection = .vertical
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = UIColor.white
        // CalendarDayCell는 별도 파일에서 단 한 번만 선언되어 있다고 가정합니다.
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
        view.backgroundColor = UIColor.white
        navigationItem.title = "Add Schedule By DATE"

        // 상단 달 컨트롤 뷰 추가
        view.addSubview(monthControlView)
        monthControlView.addSubview(monthStackView)
        monthStackView.addArrangedSubview(prevButton)
        monthStackView.addArrangedSubview(monthLabel)
        monthStackView.addArrangedSubview(nextButton)

        // 달 이동 버튼 액션 연결
        prevButton.addTarget(self, action: #selector(prevMonth), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextMonth), for: .touchUpInside)

        // CollectionView 추가
        view.addSubview(collectionView)
        collectionView.delegate = self
        collectionView.dataSource = self

        setupConstraints()
        updateLayoutForOrientation(size: view.bounds.size)
        updateMonthLabel()

        // 저장된 스케줄 불러오기 (imported schedules와 manual schedules 병합)
        loadSchedules()

        // 휴일 정보 불러오기 (현재 달 기준)
        fetchHolidays(for: currentDate)

        // 스케줄 저장 후 자동 리프레시를 위한 알림 옵저빙
        NotificationCenter.default.addObserver(self, selector: #selector(scheduleSaved(_:)), name: NSNotification.Name("ScheduleSaved"), object: nil)
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
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 스케줄 불러오기 (imported + manual schedules 병합)
    func loadSchedules() {
        var importedSchedules = [String: [[String: String]]]()
        if let data = UserDefaults.standard.data(forKey: schedulesUserDefaultsKey) {
            do {
                importedSchedules = try JSONDecoder().decode([String: [[String: String]]].self, from: data)
                print("Successfully loaded imported schedules")
            } catch {
                print("Failed to load imported schedules: \(error)")
            }
        } else {
            print("No imported schedules found.")
        }

        var manualSchedules = [String: [[String: String]]]()
        if let manualData = UserDefaults.standard.data(forKey: "manualSchedules") {
            do {
                manualSchedules = try JSONDecoder().decode([String: [[String: String]]].self, from: manualData)
                print("Successfully loaded manual schedules")
            } catch {
                print("Failed to load manual schedules: \(error)")
            }
        } else {
            print("No manual schedules found.")
        }

        // 두 데이터를 병합 (동일 날짜의 스케줄은 배열로 합치기)
        schedules = importedSchedules
        for (dateKey, manualArray) in manualSchedules {
            if var existingArray = schedules[dateKey] {
                existingArray.append(contentsOf: manualArray)
                schedules[dateKey] = existingArray
            } else {
                schedules[dateKey] = manualArray
            }
        }
    }

    // MARK: - 제약조건 설정
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

    // MARK: - 화면 회전 시 레이아웃 조정
    func updateLayoutForOrientation(size: CGSize) {
        let isLandscape = size.width > size.height
        let isiPhone = UIDevice.current.userInterfaceIdiom == .phone

        if isiPhone && isLandscape {
            monthControlHeightConstraint.constant = 20
            collectionViewTopConstraint.constant = 2
            monthLabel.font = UIFont.scaledBoldFont(ofSize: 14)
        } else {
            monthControlHeightConstraint.constant = 40
            collectionViewTopConstraint.constant = 10
            monthLabel.font = UIFont.scaledBoldFont(ofSize: 20)
        }
    }

    // MARK: - 월 라벨 업데이트
    func updateMonthLabel() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM yyyy"
        monthLabel.text = formatter.string(from: currentDate)
    }

    // MARK: - UICollectionViewDataSource
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return 49  // 7 요일 헤더 + 42 셀
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "dayCell", for: indexPath) as! CalendarDayCell
        let isLandscape = view.bounds.width > view.bounds.height
        let isiPhone = UIDevice.current.userInterfaceIdiom == .phone

        if indexPath.item < 7 {
            // 헤더 셀: 요일 표시
            cell.isHeader = true
            cell.dateLabel.text = daysOfWeek[indexPath.item]
            let headerFontSize: CGFloat = (isiPhone && isLandscape) ? 6 : 10
            cell.dateLabel.font = UIFont.boldSystemFont(ofSize: headerFontSize)
            cell.dateLabel.textColor = UIColor.black
            cell.scheduleStackView.isHidden = true
            cell.contentView.backgroundColor = UIColor.clear
        } else {
            cell.isHeader = false
            // 재사용 문제로 기존 스택뷰의 서브뷰 제거
            cell.scheduleStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

            // 날짜 계산 (월간 캘린더와 동일한 방식)
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
            var textColor: UIColor = UIColor.black

            if dayNumber < 1 {
                // 이전 달 날짜
                if let previousMonth = calendar.date(byAdding: .month, value: -1, to: currentDate),
                   let previousRange = calendar.range(of: .day, in: .month, for: previousMonth) {
                    let day = previousRange.count + dayNumber
                    cell.contentView.backgroundColor = UIColor(named: "LightGreen")
                    textColor = UIColor(named: "DarkGreen") ?? UIColor.green
                    var prevComponents = calendar.dateComponents([.year, .month], from: previousMonth)
                    prevComponents.day = day
                    displayDate = calendar.date(from: prevComponents)
                }
            } else if dayNumber > currentMonthDays {
                // 다음 달 날짜
                let day = dayNumber - currentMonthDays
                cell.contentView.backgroundColor = UIColor(named: "LightGreen")
                textColor = UIColor(named: "DarkGreen") ?? UIColor.green
                if let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentDate) {
                    var nextComponents = calendar.dateComponents([.year, .month], from: nextMonth)
                    nextComponents.day = day
                    displayDate = calendar.date(from: nextComponents)
                }
            } else {
                // 현재 달 날짜
                cell.contentView.backgroundColor = UIColor.white
                textColor = UIColor.black
                var currentComponents = calendar.dateComponents([.year, .month], from: currentDate)
                currentComponents.day = dayNumber
                displayDate = calendar.date(from: currentComponents)
            }

            // displayDate 안전하게 추출
            guard let validDisplayDate = displayDate else {
                cell.dateLabel.text = "LAYOVER"
                return cell
            }

            // 날짜 텍스트 표시
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "MMM dd"
            let dateText = dateFormatter.string(from: validDisplayDate)

            // 휴일 처리 (UTC 기준)
            let utcFormatter = DateFormatter()
            utcFormatter.locale = Locale(identifier: "en_US_POSIX")
            utcFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            utcFormatter.dateFormat = "yyyy-MM-dd"
            if let adjustedDate = calendar.date(byAdding: .day, value: 1, to: validDisplayDate) {
                let holidayKey = utcFormatter.string(from: adjustedDate)
                if let holiday = holidays[holidayKey] {
                    cell.dateLabel.text = dateText + " [\(holiday)]"
                    cell.contentView.backgroundColor = UIColor(named: "LightYellow")
                    cell.dateLabel.textColor = UIColor(named: "DarkYellow") ?? UIColor.yellow
                } else {
                    cell.dateLabel.text = dateText
                    cell.dateLabel.textColor = textColor
                }
            } else {
                cell.dateLabel.text = dateText
                cell.dateLabel.textColor = textColor
            }
            let dateFontSize: CGFloat = (isiPhone && isLandscape) ? 7 : 10
            cell.dateLabel.font = UIFont.boldSystemFont(ofSize: dateFontSize)

            // 스케줄 필터링 (날짜 비교)
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
                            // 오버나이트 스케줄: 출발일 또는 도착일과 일치하면 포함
                            if calendar.isDate(validDisplayDate, inSameDayAs: depDate) ||
                               calendar.isDate(validDisplayDate, inSameDayAs: arrDate) {
                                schedulesForCell.append(schedule)
                            }
                        } else {
                            // 일반 스케줄: validDisplayDate가 출발일과 도착일 사이에 있으면 포함
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
            
            // 스케줄 요약 표시
            if !schedulesForCell.isEmpty || self.shouldDisplayLayover(for: validDisplayDate) {
                var flightSummaries: [String] = []
                var dutyCount = 0
                var doActivityFound = false
                
                for schedule in schedulesForCell {
                    let workType = schedule["WorkType"] ?? ""
                    if workType == "FLY" {
                        let depAp = schedule["DepAp"] ?? "N/A"
                        let arrAp = schedule["ArrAp"] ?? "N/A"
                        flightSummaries.append("✈️ \(depAp) - \(arrAp)")
                    } else if workType == "TVL" {
                        let depAp = schedule["DepAp"] ?? "N/A"
                        let arrAp = schedule["ArrAp"] ?? "N/A"
                        flightSummaries.append("📌 \(depAp) - \(arrAp)")
                    } else {
                        let activity = schedule["Activity"] ?? ""
                        if activity == "DO" {
                            doActivityFound = true
                        } else {
                            dutyCount += 1
                        }
                    }
                }
                
                var summaryComponents: [String] = []
                if !flightSummaries.isEmpty {
                    summaryComponents.append(flightSummaries.joined(separator: "\n"))
                }
                if doActivityFound {
                    summaryComponents.append("🏠(\(dutyCount))")
                } else if dutyCount > 0 {
                    summaryComponents.append("🏢(\(dutyCount))")
                }
                if schedulesForCell.isEmpty && self.shouldDisplayLayover(for: validDisplayDate) {
                    summaryComponents.append("LAYOVER")
                }
                let summaryText = summaryComponents.joined(separator: "\n")
                let scheduleLabel = UILabel()
                let scheduleFontSize: CGFloat = (isiPhone && isLandscape) ? 5 : 8
                scheduleLabel.font = UIFont.boldSystemFont(ofSize: scheduleFontSize)
                scheduleLabel.textAlignment = .left
                scheduleLabel.textColor = textColor
                scheduleLabel.numberOfLines = 0
                scheduleLabel.text = summaryText
                cell.scheduleStackView.addArrangedSubview(scheduleLabel)
            }
        }
        return cell
    }

    // MARK: - UICollectionViewDelegateFlowLayout
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let flowLayout = collectionViewLayout as! UICollectionViewFlowLayout
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

    // MARK: - 날짜 선택 시 스케줄 입력 팝업 띄우기
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
               let previousRange = calendar.range(of: .day, in: .month, for: previousMonth) {
                let day = previousRange.count + dayNumber
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
        if let inputFormVC = storyboard.instantiateViewController(withIdentifier: "ScheduleInputFormModifiedViewController") as? ScheduleInputFormModifiedViewController {
            inputFormVC.selectedDate = selectedDate
            inputFormVC.modalPresentationStyle = .formSheet
            present(inputFormVC, animated: true, completion: nil)
        }
    }

    // MARK: - 달 이동 메서드
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

    // MARK: - 휴일 정보 가져오기
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
            print("Failed to create URL")
            return
        }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                print("API request error: \(error.localizedDescription)")
                return
            }
            guard let data = data else {
                print("No data returned")
                return
            }
            if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let items = jsonObject["items"] as? [[String: Any]] {
                for item in items {
                    if let startInfo = item["start"] as? [String: Any],
                       let startDateStr = startInfo["date"] as? String,
                       let summary = item["summary"] as? String {
                        // API에서 받은 날짜 문자열 그대로 사용 (예: "2025-03-01")
                        self.holidays[startDateStr] = summary
                    }
                }
                DispatchQueue.main.async {
                    self.collectionView.reloadData()
                }
            } else {
                print("JSON response format error")
            }
        }
        task.resume()
    }

    // MARK: - 스케줄 저장 알림 처리 (자동 리프레시)
    @objc func scheduleSaved(_ notification: Notification) {
        fetchHolidays(for: currentDate)
        loadSchedules()
        collectionView.reloadData()
    }

    // MARK: - Layover 여부 확인 (동일한 로직)
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
}
