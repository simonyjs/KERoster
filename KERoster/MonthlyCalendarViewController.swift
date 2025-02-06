//
//  MonthlyCalendarViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/02/04.
//

import UIKit

class MonthlyCalendarViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    // 스케줄 데이터: 키는 원래 "dd-MMM-yyyy" 형식이나,
    // 실제로는 각 스케줄 항목 내에 "DepDate"와 "ArrDate"가 포함되어 있음.
    var schedules: [String: [[String: String]]] = [:]
    
    // 날짜별 휴일 정보를 저장 (키: "yyyy-MM-dd")
    var holidays: [String: String] = [:]
    
    // 현재 보여지는 날짜 (월 단위)
    var currentDate = Date()
    
    // 현재 사용 중인 Calendar 객체
    let calendar = Calendar.current
    
    // 상단 월 컨트롤 뷰 (배경색 삭제)
    let monthControlView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
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
    
    // monthLabel: "MMMM yyyy" 형식의 월 표시
    let monthLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.boldSystemFont(ofSize: 20)
        label.textAlignment = .center
        label.textColor = .black
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
        
        // 상단 컨트롤 뷰 추가
        view.addSubview(monthControlView)
        monthControlView.addSubview(prevButton)
        monthControlView.addSubview(monthLabel)
        monthControlView.addSubview(nextButton)
        
        // 이전/다음 버튼 액션 설정
        prevButton.addTarget(self, action: #selector(prevMonth), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextMonth), for: .touchUpInside)
        
        // 컬렉션 뷰 추가 및 데이터소스, 델리게이트 설정
        view.addSubview(collectionView)
        collectionView.delegate = self
        collectionView.dataSource = self
        
        // 제약조건 설정
        setupConstraints()
        updateMonthLabel()
        fetchHolidays(for: currentDate)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.collectionViewLayout.invalidateLayout()
    }
    
    // MARK: - Auto Layout 제약조건 설정
    func setupConstraints() {
        NSLayoutConstraint.activate([
            // 상단 월 컨트롤 뷰
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
    
    // MARK: - API 호출: 휴일 정보 가져오기
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
    
    // 월 레이블 업데이트 ("MMMM yyyy")
    func updateMonthLabel() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM yyyy"
        monthLabel.text = formatter.string(from: currentDate)
    }
    
    // MARK: - UICollectionViewDataSource
    
    // 총 49개 셀: 7개는 요일 헤더, 나머지는 날짜 셀
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return 49
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        // 커스텀 셀(CalendarDayCell) 가져오기
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "dayCell", for: indexPath) as! CalendarDayCell
        
        // 0~6: 요일 헤더 셀
        if indexPath.item < 7 {
            cell.isHeader = true
            cell.dateLabel.text = daysOfWeek[indexPath.item]
            cell.dateLabel.font = UIFont.boldSystemFont(ofSize: 14)
            cell.dateLabel.textColor = .black
            cell.scheduleStackView.isHidden = true
            cell.contentView.backgroundColor = UIColor(red: 0.9686, green: 0.8549, blue: 0.3922, alpha: 1.0)  // #f7da64
        } else {
            // 날짜 셀: 요일 헤더 이후의 인덱스 처리
            cell.isHeader = false
            
            // 현재 달의 첫 번째 날짜 계산
            let components = calendar.dateComponents([.year, .month], from: currentDate)
            guard let firstDayOfMonth = calendar.date(from: components) else { return cell }
            
            // 첫 날의 요일 (일요일이 1, 토요일이 7)
            let weekday = calendar.component(.weekday, from: firstDayOfMonth)
            var offset = weekday - calendar.firstWeekday
            if offset < 0 { offset += 7 }
            
            let index = indexPath.item - 7
            let dayNumber = index - offset + 1
            
            let currentMonthRange = calendar.range(of: .day, in: .month, for: currentDate)!
            let currentMonthDays = currentMonthRange.count
            
            var displayDate: Date?
            var textColor: UIColor = .black
            var isOutsideMonth = false
            
            // 이전 달에 속하는 날짜 처리
            if dayNumber < 1 {
                if let previousMonth = calendar.date(byAdding: .month, value: -1, to: currentDate),
                   let previousMonthRange = calendar.range(of: .day, in: .month, for: previousMonth) {
                    let previousMonthDays = previousMonthRange.count
                    let day = previousMonthDays + dayNumber
                    textColor = .lightGray
                    isOutsideMonth = true
                    var prevComponents = calendar.dateComponents([.year, .month], from: previousMonth)
                    prevComponents.day = day
                    displayDate = calendar.date(from: prevComponents)
                }
            }
            // 다음 달에 속하는 날짜 처리
            else if dayNumber > currentMonthDays {
                let day = dayNumber - currentMonthDays
                textColor = .lightGray
                isOutsideMonth = true
                if let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentDate) {
                    var nextComponents = calendar.dateComponents([.year, .month], from: nextMonth)
                    nextComponents.day = day
                    displayDate = calendar.date(from: nextComponents)
                }
            }
            // 현재 달에 속하는 날짜 처리
            else {
                textColor = .black
                var currentComponents = calendar.dateComponents([.year, .month], from: currentDate)
                currentComponents.day = dayNumber
                displayDate = calendar.date(from: currentComponents)
            }
            
            // 날짜 레이블에 표시할 텍스트 포맷 (예: "MMM dd")
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
            
            // 이전에 추가된 스케줄 뷰 제거
            cell.scheduleStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
            
            // 휴일 표시 처리 (날짜 포맷: "yyyy-MM-dd")
            if let displayDate = displayDate {
                let holidayFormatter = DateFormatter()
                holidayFormatter.locale = Locale(identifier: "en_US_POSIX")
                holidayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                holidayFormatter.dateFormat = "yyyy-MM-dd"
                // +1일 옵셋을 적용한 키 (API에서 받은 날짜와 일치하도록 함)
                let holidayKey = holidayFormatter.string(from: calendar.date(byAdding: .day, value: +1, to: displayDate)!)
                
                if let holiday = holidays[holidayKey] {
                    cell.dateLabel.text = "[\(holiday)] " + dateText
                    if isOutsideMonth {
                        cell.contentView.backgroundColor = UIColor(red: 0.6078, green: 0.7137, blue: 0.7804, alpha: 1.0) // #9bb6c7
                        cell.dateLabel.textColor = .gray
                    } else {
                        cell.contentView.backgroundColor = UIColor(red: 0.9255, green: 0.4196, blue: 0.3412, alpha: 1.0) // #ec6b57 (휴일)
                    }
                } else {
                    if isOutsideMonth {
                        cell.contentView.backgroundColor = UIColor(red: 0.3804, green: 0.7412, blue: 0.4314, alpha: 1.0) // #61bd6e
                        cell.dateLabel.textColor = .gray
                    } else {
                        cell.contentView.backgroundColor = .white
                    }
                }
                
                // ──────────────────────────────────────────────
                // **변경된 부분: 달력 셀에 스케줄 표시하기 위한 날짜 범위 체크**
                //
                // 기존에는 displayDate를 "dd-MMM-yyyy" 문자열로 변환하여 schedules 딕셔너리에서 해당 키로 스케줄을 가져왔으나,
                // 이제는 각 스케줄 항목의 "DepDate"와 "ArrDate"를 파싱한 후,
                // displayDate가 그 기간 내에 포함되는지를 확인하여 셀에 표시합니다.
                //
                // 스케줄 데이터는 schedules 딕셔너리의 모든 값을 순회하여 확인합니다.
                // ──────────────────────────────────────────────
                
                // 준비: 스케줄 항목의 날짜 파싱을 위한 포매터 (입력 포맷: "dd-MMM-yyyy")
                let scheduleDateFormatter = DateFormatter()
                scheduleDateFormatter.locale = Locale(identifier: "en_US_POSIX")
                scheduleDateFormatter.dateFormat = "dd-MMM-yyyy"
                
                // 해당 셀에 해당하는 날짜(displayDate)와 비교할 스케줄 목록
                var schedulesForCell: [[String: String]] = []
                
                // schedules 딕셔너리의 모든 스케줄 항목을 순회
                for (_, scheduleArray) in schedules {
                    for schedule in scheduleArray {
                        // 스케줄 항목에서 DepDate와 ArrDate 가져오기
                        if let depDateStr = schedule["DepDate"],
                           let arrDateStr = schedule["ArrDate"],
                           let depDate = scheduleDateFormatter.date(from: depDateStr),
                           let arrDate = scheduleDateFormatter.date(from: arrDateStr) {
                            
                            // displayDate가 DepDate와 ArrDate 사이에 포함되면 해당 스케줄을 추가
                            if displayDate >= depDate && displayDate <= arrDate {
                                schedulesForCell.append(schedule)
                            }
                        }
                        // 만약 ArrDate가 없는 경우, DepDate만을 기준으로 같은 날짜인지 체크
                        else if let depDateStr = schedule["DepDate"],
                                let depDate = scheduleDateFormatter.date(from: depDateStr) {
                            if calendar.isDate(displayDate, inSameDayAs: depDate) {
                                schedulesForCell.append(schedule)
                            }
                        }
                    }
                }
                
                // 스케줄 목록을 해당 셀의 스택뷰에 표시
                for schedule in schedulesForCell {
                    let scheduleLabel = UILabel()
                    scheduleLabel.font = UIFont.boldSystemFont(ofSize: 10)
                    scheduleLabel.textAlignment = .left
                    // 날짜가 현재 달에 속하지 않으면 회색으로 표시
                    scheduleLabel.textColor = isOutsideMonth ? .gray : .black
                    scheduleLabel.numberOfLines = 0
                    
                    // 스케줄의 WorkType에 따라 표시 형식 변경
                    if let workType = schedule["WorkType"], workType == "FLY" || workType == "TVL" {
                        var item = schedule["Item"] ?? ""
                        // TVL인 경우 item의 앞 두 문자를 변경
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
                        
                        // DepDate와 ArrDate가 다를 경우, 분할하여 표시
                        let depDate = schedule["DepDate"] ?? ""
                        let arrDate = schedule["ArrDate"] ?? ""
                        
                        // displayDate를 "dd-MMM-yyyy" 형식의 문자열로 변환 (scheduleDateFormatter는 이미 선언되어 있다고 가정)
                        let cellDateString = scheduleDateFormatter.string(from: displayDate)

                        if !depDate.isEmpty && !arrDate.isEmpty && depDate != arrDate {
                            // 만약 셀의 날짜가 DepDate와 같다면 출발 시간 기준으로 표시
                            if cellDateString == depDate {
                                scheduleLabel.text = "\(item) \(depTime) \(depAp) - \(arrAp) 23:59"
                            }
                            // 만약 셀의 날짜가 ArrDate와 같다면 도착 시간 기준으로 표시
                            else if cellDateString == arrDate {
                                scheduleLabel.text = "\(item) 00:00 \(depAp) - \(arrAp) \(arrTime)"
                            }
                            else {
                                // 셀의 날짜가 DepDate와 ArrDate 모두와 일치하지 않으면 해당 스케줄은 건너뜁니다.
                                continue
                            }
                        } else {
                            scheduleLabel.text = "\(item) \(depTime) \(depAp) - \(arrAp) \(arrTime)"
                        }

                    } else {
                        // WorkType가 FLY나 TVL이 아닌 경우: 활동 정보 표시
                        let activity = schedule["Activity"] ?? ""
                        let dutyReport = schedule["DutyReport"] ?? ""
                        let dutyDebrief = schedule["DutyDebrief"] ?? ""
                        scheduleLabel.text = "\(activity) \(dutyReport) - \(dutyDebrief)"
                    }
                    // 스케줄 레이블을 스택뷰에 추가
                    cell.scheduleStackView.addArrangedSubview(scheduleLabel)
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
        stackView.alignment = .leading // 왼쪽 정렬
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    // isHeader: true이면 요일 셀, false이면 날짜 셀
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
        // 일반 날짜 셀: 날짜는 왼쪽 상단, 스케줄은 날짜 바로 아래에 표시
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
        // 헤더 셀: 요일 레이블을 중앙에 배치
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
