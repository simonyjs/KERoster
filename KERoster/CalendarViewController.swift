//
//  CalendarViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/02/02.
//

import UIKit
//import JTAppleCalendar

class CalendarViewController: UIViewController {
    
    // JTAppleCalendarView 인스턴스 (스토리보드 대신 코드로 생성)
    let calendarView = JTAppleCalendarView()
    
    // 기존에 가져온 schedules 데이터
    // 예: ["22-Jan-2025": [schedule1, schedule2], "23-Jan-2025": [schedule3], ...]
    var schedules: [String: [[String: String]]] = [:]
    
    // 스케줄이 있는 날짜들을 Date 형식으로 저장 (빠른 조회용)
    var scheduleDates: Set<Date> = []
    
    // DateFormatter: 스케줄 데이터의 날짜 문자열("dd-MMM-yyyy")를 Date로 변환
    let inputFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "dd-MMM-yyyy"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()
    
    // 출력용 DateFormatter (예: "yyyy-MM-dd")
    let displayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Calendar View"
        view.backgroundColor = .white
        
        setupCalendarView()
        processScheduleDates()
    }
    
    private func setupCalendarView() {
        // JTAppleCalendarView 설정 (프레임은 필요에 따라 조정)
        calendarView.calendarDataSource = self
        calendarView.calendarDelegate = self
        calendarView.register(CalendarCell.self, forCellWithReuseIdentifier: "CalendarCell")
        calendarView.minimumLineSpacing = 0
        calendarView.minimumInteritemSpacing = 0
        calendarView.backgroundColor = .white
        
        view.addSubview(calendarView)
        calendarView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            calendarView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            calendarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            calendarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            calendarView.heightAnchor.constraint(equalToConstant: 350)
        ])
    }
    
    /// schedules의 키(문자열)를 Date로 변환하여 scheduleDates 집합에 추가합니다.
    private func processScheduleDates() {
        for (dateString, _) in schedules {
            if let date = inputFormatter.date(from: dateString) {
                scheduleDates.insert(date)
            }
        }
        calendarView.reloadData()
    }
}

// MARK: - JTAppleCalendarViewDataSource
extension CalendarViewController: JTAppleCalendarViewDataSource {
    func configureCalendar(_ calendar: JTAppleCalendarView) -> ConfigurationParameters {
        // 달력 표시 범위를 설정합니다. (예: 2025년 1월 1일부터 2025년 12월 31일까지)
        let startDate = inputFormatter.date(from: "01-Jan-2025")!
        let endDate = inputFormatter.date(from: "31-Dec-2025")!
        let parameters = ConfigurationParameters(startDate: startDate,
                                                 endDate: endDate,
                                                 numberOfRows: 6,
                                                 calendar: Calendar.current,
                                                 generateInDates: .forAllMonths,
                                                 generateOutDates: .tillEndOfRow,
                                                 firstDayOfWeek: .sunday)
        return parameters
    }
}

// MARK: - JTAppleCalendarViewDelegate
extension CalendarViewController: JTAppleCalendarViewDelegate {
    func calendar(_ calendar: JTAppleCalendarView,
                  cellForItemAt date: Date,
                  cellState: CellState,
                  indexPath: IndexPath) -> JTAppleCalendarViewCell {
        let cell = calendar.dequeueReusableJTAppleCell(withReuseIdentifier: "CalendarCell", for: indexPath) as! CalendarCell
        cell.dateLabel.text = cellState.text
        
        // 일정이 있는 날짜면 eventView 표시
        if scheduleDates.contains(where: { Calendar.current.isDate($0, inSameDayAs: date) }) {
            cell.eventView.isHidden = false
        } else {
            cell.eventView.isHidden = true
        }
        return cell
    }
    
    func calendar(_ calendar: JTAppleCalendarView,
                  didSelectDate date: Date,
                  cell: JTAppleCalendarViewCell?,
                  cellState: CellState,
                  indexPath: IndexPath) {
        // 선택한 날짜의 문자열(표시용)
        let displayDate = displayFormatter.string(from: date)
        // schedules 데이터는 키가 "dd-MMM-yyyy" 형식이므로 다시 변환합니다.
        let key = inputFormatter.string(from: date)
        if let schedulesForDate = schedules[key] {
            let message = schedulesForDate.map { schedule in
                let activity = schedule["Activity"] ?? "No Activity"
                return "\(activity)"
            }.joined(separator: "\n")
            
            let alert = UIAlertController(title: "Schedules on \(displayDate)",
                                          message: message,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Close", style: .default))
            present(alert, animated: true)
        } else {
            let alert = UIAlertController(title: "No Schedule",
                                          message: "There is no schedule for \(displayDate).",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Close", style: .default))
            present(alert, animated: true)
        }
    }
    
    // (선택사항) 날짜 셀의 배경색 또는 텍스트 색상을 커스터마이징할 수 있습니다.
    func calendar(_ calendar: JTAppleCalendarView,
                  didScrollToDateSegmentWith visibleDates: DateSegmentInfo) {
        // 예: 상단에 현재 표시 중인 달을 title로 업데이트하는 등의 작업
    }
}

// MARK: - Custom Calendar Cell
class CalendarCell: JTAppleCalendarViewCell {
    let dateLabel = UILabel()
    let eventView = UIView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCellView()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupCellView()
    }
    
    private func setupCellView() {
        // 날짜 레이블 설정
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.textAlignment = .center
        contentView.addSubview(dateLabel)
        NSLayoutConstraint.activate([
            dateLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            dateLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
        
        // 이벤트 표시용 작은 원 (예: 빨간 점)
        eventView.translatesAutoresizingMaskIntoConstraints = false
        eventView.backgroundColor = .red
        eventView.layer.cornerRadius = 3
        contentView.addSubview(eventView)
        NSLayoutConstraint.activate([
            eventView.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 2),
            eventView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            eventView.widthAnchor.constraint(equalToConstant: 6),
            eventView.heightAnchor.constraint(equalToConstant: 6)
        ])
        eventView.isHidden = true
    }
}
