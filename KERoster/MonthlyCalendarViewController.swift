//
//  MonthlyCalendarViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/02/04.
//

import UIKit

class MonthlyCalendarViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    // 날짜별 일정 정보를 저장하는 딕셔너리 (ViewListViewController와 동일하게 "dd-MMM-yyyy" 형식의 키 사용)
    var schedules: [String: [[String: String]]] = [:]
    
    // 날짜별 휴일 정보를 저장하는 딕셔너리
    // 공휴일 데이터는 "yyyy-MM-dd" 형식으로 저장되어 있다고 가정
    var holidays: [String: String] = [:]
    
    // 현재 보여지는 날짜 (월 단위)
    var currentDate = Date()
    
    // 현재 사용 중인 Calendar 객체
    let calendar = Calendar.current
    
    // 상단의 월 컨트롤 뷰 (이전 버튼, 월 라벨, 다음 버튼) – 월 표시 배경은 삭제(= clear)
    let monthControlView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear  // 배경 삭제
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // 이전 버튼
    let prevButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("⬅️", for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // 다음 버튼
    let nextButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("➡️", for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // monthLabel: "MMMM yyyy" 형식 (예: February 2025)
    let monthLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.boldSystemFont(ofSize: 20)
        label.textAlignment = .center
        label.textColor = .black
        // 월 표시 배경은 삭제하므로 별도 배경색 지정 없음
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // 달력의 날짜들을 표시할 컬렉션 뷰
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
    
    // 요일 이름 배열
    let daysOfWeek = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    
    // MARK: - View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        
        navigationItem.title = "ROSTER SUMMARY"
        
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
        updateMonthLabel()
        fetchHolidays(for: currentDate)
        
        // 임시 스케줄 데이터 (디버깅용)
        // schedules["22-Jan-2025"] = [
        //     ["Activity": "회의", "WorkType": "MEETING", "DutyReport": "09:00", "DutyDebrief": "10:00"],
        //     ["WorkType": "FLY", "Item": "Flight 101", "DepAp": "ICN", "ArrAp": "LAX", "DepStnTime": "11:00", "ArrStnTime": "16:00"]
        // ]
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.collectionViewLayout.invalidateLayout()
    }
    
    // MARK: - Auto Layout 제약조건 설정
    func setupConstraints() {
        NSLayoutConstraint.activate([
            monthControlView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            monthControlView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            monthControlView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            monthControlView.heightAnchor.constraint(equalToConstant: 40),
            
            prevButton.leadingAnchor.constraint(equalTo: monthControlView.leadingAnchor),
            prevButton.centerYAnchor.constraint(equalTo: monthControlView.centerYAnchor),
            prevButton.widthAnchor.constraint(equalToConstant: 80),
            
            nextButton.trailingAnchor.constraint(equalTo: monthControlView.trailingAnchor),
            nextButton.centerYAnchor.constraint(equalTo: monthControlView.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 80),
            
            monthLabel.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: 10),
            monthLabel.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -10),
            monthLabel.centerYAnchor.constraint(equalTo: monthControlView.centerYAnchor),
            
            collectionView.topAnchor.constraint(equalTo: monthControlView.bottomAnchor, constant: 10),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - API 호출 및 JSON 파싱 (구글 캘린더 API 사용)
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
                    print("JSON 응답이 [String: Any] 형식이 아님")
                }
            } catch {
                print("JSON 파싱 오류: \(error.localizedDescription)")
            }
        }
        task.resume()
    }
    
    // MARK: - 월 이동 액션
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
    
    // monthLabel 업데이트 ("MMMM yyyy" 형식)
    func updateMonthLabel() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM yyyy"
        monthLabel.text = formatter.string(from: currentDate)
    }
    
    // MARK: - UICollectionViewDataSource
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return 49
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "dayCell", for: indexPath) as! CalendarDayCell
        
        if indexPath.item < 7 {
            // 헤더 셀: 요일 표시 (무조건 검은색 굵은 글씨, 배경 #f7da64)
            cell.isHeader = true
            cell.dateLabel.text = daysOfWeek[indexPath.item]
            cell.dateLabel.font = UIFont.boldSystemFont(ofSize: 14)
            cell.dateLabel.textColor = .black
            cell.scheduleStackView.isHidden = true
            cell.contentView.backgroundColor = UIColor(red: 0.9686, green: 0.8549, blue: 0.3922, alpha: 1.0)  // #f7da64
        } else {
            // 일반 날짜 셀: 날짜는 왼쪽 위에, 스케줄은 날짜 바로 아래 왼쪽 정렬
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
            
            // 날짜가 현재 월에 속하지 않는지 판별
            let isOutsideMonth = (dayNumber < 1 || dayNumber > currentMonthDays)
            
            if dayNumber < 1 {
                if let previousMonth = calendar.date(byAdding: .month, value: -1, to: currentDate),
                   let previousMonthRange = calendar.range(of: .day, in: .month, for: previousMonth) {
                    let previousMonthDays = previousMonthRange.count
                    let day = previousMonthDays + dayNumber
                    textColor = .lightGray
                    var prevComponents = calendar.dateComponents([.year, .month], from: previousMonth)
                    prevComponents.day = day
                    displayDate = calendar.date(from: prevComponents)
                }
            } else if dayNumber > currentMonthDays {
                let day = dayNumber - currentMonthDays
                textColor = .lightGray
                if let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentDate) {
                    var nextComponents = calendar.dateComponents([.year, .month], from: nextMonth)
                    nextComponents.day = day
                    displayDate = calendar.date(from: nextComponents)
                }
            } else {
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
                cell.dateLabel.text = ""
            }
            cell.dateLabel.font = UIFont.boldSystemFont(ofSize: 12)
            cell.dateLabel.textColor = textColor
            
            cell.scheduleStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
            
            if let displayDate = displayDate {
                let holidayFormatter = DateFormatter()
                holidayFormatter.locale = Locale(identifier: "en_US_POSIX")
                holidayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                holidayFormatter.dateFormat = "yyyy-MM-dd"
                // 기존 +1일 옵셋 유지
                let holidayKey = holidayFormatter.string(from: calendar.date(byAdding: .day, value: +1, to: displayDate)!)
                
                if let holiday = holidays[holidayKey] {
                    cell.dateLabel.text = "[\(holiday)] " + dateText
                    // 휴일 셀 배경색: #ec6b57
                    if isOutsideMonth {
                        cell.contentView.backgroundColor = UIColor(red: 0.6078, green: 0.7137, blue: 0.7804, alpha: 1.0) // #9bb6c7 (외부 날짜)
                        cell.dateLabel.textColor = .gray
                    } else {
                        cell.contentView.backgroundColor = UIColor(red: 0.9255, green: 0.4196, blue: 0.3412, alpha: 1.0) // #ec6b57 (휴일)
                    }
                } else {
                    if isOutsideMonth {
                        cell.contentView.backgroundColor = UIColor(red: 0.3804, green: 0.7412, blue: 0.4314, alpha: 1.0) // #61bd6e (해당월 외)
                        cell.dateLabel.textColor = .gray
                    } else {
                        cell.contentView.backgroundColor = .white
                    }
                }
                
                let scheduleFormatter = DateFormatter()
                scheduleFormatter.locale = Locale(identifier: "en_US_POSIX")
                scheduleFormatter.dateFormat = "dd-MMM-yyyy"
                let originalDateKey = scheduleFormatter.string(from: displayDate)
                
                if let dailySchedules = schedules[originalDateKey] {
                    for schedule in dailySchedules {
                        let scheduleLabel = UILabel()
                        scheduleLabel.font = UIFont.boldSystemFont(ofSize: 10)
                        scheduleLabel.textColor = .black
                        scheduleLabel.textAlignment = .left
                        scheduleLabel.numberOfLines = 0
                        
                        if let workType = schedule["WorkType"], workType == "FLY" || workType == "TVL" {
                            let item = schedule["Item"] ?? ""
                            let depTime = schedule["DepStnTime"] ?? ""
                            let depAp = schedule["DepAp"] ?? ""
                            let arrAp = schedule["ArrAp"] ?? ""
                            let arrTime = schedule["ArrStnTime"] ?? ""
                            scheduleLabel.text = "\(item) \(depTime) \(depAp) - \(arrAp) \(arrTime)"
                        } else {
                            let activity = schedule["Activity"] ?? ""
                            let dutyReport = schedule["DutyReport"] ?? ""
                            let dutyDebrief = schedule["DutyDebrief"] ?? ""
                            scheduleLabel.text = "\(activity) \(dutyReport) - \(dutyDebrief)"
                        }
                        cell.scheduleStackView.addArrangedSubview(scheduleLabel)
                    }
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

// MARK: - CalendarDayCell
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
    
    // isHeader: true이면 요일 셀, false이면 날짜 셀로 레이아웃 변경
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
        contentView.layer.borderColor = UIColor.lightGray.cgColor
        
        contentView.addSubview(dateLabel)
        contentView.addSubview(scheduleStackView)
        
        setupNormalConstraints()
        setupHeaderConstraints()
        updateLayoutForHeader()
    }
    
    private func setupNormalConstraints() {
        // 일반 날짜 셀: 날짜는 왼쪽 위, 스케줄은 날짜 바로 아래에 왼쪽 정렬
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
        // 헤더 셀: 날짜 레이블을 셀의 중앙에 배치
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
