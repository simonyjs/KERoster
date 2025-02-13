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
    
    // 휴일 정보를 저장할 딕셔너리 (키: "yyyy-MM-dd" 문자열)
    var holidays: [String: String] = [:]
    
    // 저장된 스케줄 데이터 (날짜 키: "dd-MMM-yyyy")
    var schedules: [String: [[String: String]]] = [:]
    
    // UserDefaults에 저장할 때 사용할 key
    let schedulesUserDefaultsKey = "schedules"
    
    // MARK: - UI Elements
    
    // 상단 달 컨트롤 뷰 (월 이동 버튼, 월 라벨)
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
    
    let monthStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.alignment = .center
        sv.distribution = .equalCentering
        sv.spacing = 8
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    
    // 달력 CollectionView (MonthlyCalendarViewController와 동일)
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
        
        // 저장된 스케줄 불러오기
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
    
    // MARK: - 스케줄 불러오기
    func loadSchedules() {
        if let data = UserDefaults.standard.data(forKey: schedulesUserDefaultsKey) {
            do {
                schedules = try JSONDecoder().decode([String: [[String: String]]].self, from: data)
                print("스케줄 불러오기 성공")
            } catch {
                print("스케줄 불러오기 실패: \(error)")
            }
        } else {
            print("저장된 스케줄이 없습니다.")
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
                // 이전 달: LightGreen 배경, DarkGreen 텍스트
                if let previousMonth = calendar.date(byAdding: .month, value: -1, to: currentDate),
                   let previousRange = calendar.range(of: .day, in: .month, for: previousMonth) {
                    let day = previousRange.count + dayNumber
                    cell.contentView.backgroundColor = UIColor(named: "LightGreen")
                    textColor = UIColor(named: "DarkGreen") ?? .green
                    var prevComponents = calendar.dateComponents([.year, .month], from: previousMonth)
                    prevComponents.day = day
                    displayDate = calendar.date(from: prevComponents)
                }
            } else if dayNumber > currentMonthDays {
                // 다음 달: LightGreen 배경, DarkGreen 텍스트
                let day = dayNumber - currentMonthDays
                cell.contentView.backgroundColor = UIColor(named: "LightGreen")
                textColor = UIColor(named: "DarkGreen") ?? .green
                if let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentDate) {
                    var nextComponents = calendar.dateComponents([.year, .month], from: nextMonth)
                    nextComponents.day = day
                    displayDate = calendar.date(from: nextComponents)
                }
            } else {
                // 현재 달: 흰색 배경, 검정 텍스트
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
                // 휴일 정보 표시
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
                    } else {
                        cell.dateLabel.text = dateText
                        cell.dateLabel.textColor = textColor
                    }
                } else {
                    cell.dateLabel.text = dateText
                    cell.dateLabel.textColor = textColor
                }
            } else {
                cell.dateLabel.text = "LAYOVER"
            }
            let dateFontSize: CGFloat = (isiPhone && isLandscape) ? 7 : 10
            cell.dateLabel.font = UIFont.boldSystemFont(ofSize: dateFontSize)
            
            // 추가: 해당 날짜에 저장된 스케줄이 있다면, 셀 하단에 요약(예: "(2)")을 표시
            let scheduleDateFormatter = DateFormatter()
            scheduleDateFormatter.locale = Locale(identifier: "en_US_POSIX")
            scheduleDateFormatter.dateFormat = "dd-MMM-yyyy"
            if let validDisplayDate = displayDate {
                let dateKey = scheduleDateFormatter.string(from: validDisplayDate)
                if let schedulesForCell = schedules[dateKey], !schedulesForCell.isEmpty {
                    let summaryLabel = UILabel()
                    summaryLabel.font = UIFont.systemFont(ofSize: (isiPhone && isLandscape) ? 5 : 8)
                    summaryLabel.textColor = textColor
                    summaryLabel.text = "(\(schedulesForCell.count))"
                    cell.scheduleStackView.addArrangedSubview(summaryLabel)
                }
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
        if indexPath.item < 7 {
            return CGSize(width: cellWidth, height: 30)
        } else {
            let lineSpacing = flowLayout.minimumLineSpacing
            let totalVerticalSpacing = flowLayout.sectionInset.top + flowLayout.sectionInset.bottom + 30 + lineSpacing * 5
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
        
        // 선택된 날짜를 문자열 형태로 변환 (키: dd-MMM-yyyy)
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MMM-yyyy"
        let selectedDateString = formatter.string(from: selectedDate)
        
        // 선택된 날짜에 대해 ScheduleInputFormViewController를 모달로 띄움
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let inputFormVC = storyboard.instantiateViewController(withIdentifier: "ScheduleInputFormViewController") as? ScheduleInputFormViewController {
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
            if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let items = jsonObject["items"] as? [[String: Any]] {
                for item in items {
                    if let startInfo = item["start"] as? [String: Any],
                       let startDateStr = startInfo["date"] as? String,
                       let summary = item["summary"] as? String {
                        self.holidays[startDateStr] = summary
                    }
                }
                DispatchQueue.main.async {
                    self.collectionView.reloadData()
                }
            } else {
                print("JSON 응답 형식 오류")
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
    
}
