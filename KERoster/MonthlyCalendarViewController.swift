//
//  MonthlyCalendarViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/02/04.
//

import UIKit

class MonthlyCalendarViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    // 날짜별 일정 정보를 저장하는 딕셔너리 (필요시 사용)
    var schedules: [String: [[String: String]]] = [:]
    // 날짜별 휴일 정보를 저장하는 딕셔너리
    var holidays: [String: String] = [:]
    // 현재 보여지는 날짜 (월 단위)
    var currentDate = Date()
    
    // 현재 사용 중인 Calendar 객체
    let calendar = Calendar.current
    
    // 상단의 월 컨트롤 뷰 (이전, 다음 버튼과 월 라벨)
    let monthControlView: UIView = {
        let view = UIView()
        // 디버깅용 배경색 (필요시 제거)
        view.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.3)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // 이전 버튼 (이모지 ⬅️ 사용)
    let prevButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("⬅️", for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // 다음 버튼 (이모지 ➡️ 사용)
    let nextButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("➡️", for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // monthLabel은 "MMMM yyyy" 형식으로 표시 (예: February 2025)
    let monthLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.boldSystemFont(ofSize: 20)
        label.textAlignment = .center
        // 글씨 색상을 검은색으로 지정
        label.textColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // 달력의 날짜들을 표시할 컬렉션 뷰
    let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 1       // 행 간격
        layout.minimumInteritemSpacing = 1   // 열 간격
        // 좌우 여백을 2로 줄여서 전체 가로폭 확보
        layout.sectionInset = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        layout.scrollDirection = .vertical
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .white
        cv.register(CalendarDayCell.self, forCellWithReuseIdentifier: "dayCell")
        // 전체 그리드를 한 화면에 표시하기 위해 스크롤 비활성화
        cv.isScrollEnabled = false
        return cv
    }()
    
    // 요일 이름 배열 (고정)
    let daysOfWeek = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    
    // MARK: - View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        
        // 내비게이션 바 중앙에 "ROSTER SUMMARY" 제목 설정
        navigationItem.title = "ROSTER SUMMARY"
        
        // monthControlView를 뷰에 추가하고, 그 안에 이전 버튼, 월 라벨, 다음 버튼 추가
        view.addSubview(monthControlView)
        monthControlView.addSubview(prevButton)
        monthControlView.addSubview(monthLabel)
        monthControlView.addSubview(nextButton)
        
        // 이전/다음 버튼 액션 등록
        prevButton.addTarget(self, action: #selector(prevMonth), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextMonth), for: .touchUpInside)
        
        view.addSubview(collectionView)
        collectionView.delegate = self
        collectionView.dataSource = self
        
        setupConstraints()
        updateMonthLabel()
        fetchHolidays(for: currentDate)
    }
    
    // 화면 회전 또는 레이아웃 변경 시 레이아웃 무효화
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.collectionViewLayout.invalidateLayout()
    }
    
    // Auto Layout 제약조건 설정
    func setupConstraints() {
        NSLayoutConstraint.activate([
            // monthControlView: 상단 safeArea에서 10포인트, 좌우 10포인트, 높이 40 (필요시 높이를 조정)
            monthControlView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            monthControlView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            monthControlView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            monthControlView.heightAnchor.constraint(equalToConstant: 40),
            
            // prevButton: monthControlView 왼쪽, 너비 80
            prevButton.leadingAnchor.constraint(equalTo: monthControlView.leadingAnchor),
            prevButton.centerYAnchor.constraint(equalTo: monthControlView.centerYAnchor),
            prevButton.widthAnchor.constraint(equalToConstant: 80),
            
            // nextButton: monthControlView 오른쪽, 너비 80
            nextButton.trailingAnchor.constraint(equalTo: monthControlView.trailingAnchor),
            nextButton.centerYAnchor.constraint(equalTo: monthControlView.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 80),
            
            // monthLabel: prevButton와 nextButton 사이, 중앙 정렬
            monthLabel.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: 10),
            monthLabel.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -10),
            monthLabel.centerYAnchor.constraint(equalTo: monthControlView.centerYAnchor),
            
            // collectionView: monthControlView 아래 10포인트, 좌우 및 하단 전체 사용
            collectionView.topAnchor.constraint(equalTo: monthControlView.bottomAnchor, constant: 10),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - API 호출 및 JSON 파싱
    func fetchHolidays(for date: Date) {
        // 월이 바뀔 때마다 기존 휴일 데이터 삭제
        holidays.removeAll()
        
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        
        // 서비스키 및 엔드포인트 URL (JSON 응답 받으려면 _type=json 추가)
        let serviceKey = "%2FzXNtT10h%2BAjsYrujOeurHWvrtKP%2BGlxSKwjtq58%2BA%2BXmw5D8uAGiS3Z%2Bq3AjZY3Wont29%2Bm4bLy2S88KzYw4A%3D%3D"
        let urlString = "https://apis.data.go.kr/B090041/openapi/service/SpcdeInfoService/getRestDeInfo?serviceKey=\(serviceKey)&solYear=\(year)&solMonth=\(String(format: "%02d", month))&_type=json"
  
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
                if let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    print("전체 JSON 응답: \(jsonObject)")
                    if let response = jsonObject["response"] as? [String: Any],
                       let body = response["body"] as? [String: Any],
                       let items = body["items"] as? [String: Any],
                       let itemArray = items["item"] as? [[String: Any]] {
                        for item in itemArray {
                            if let locdate = item["locdate"] as? Int,
                               let dateName = item["dateName"] as? String {
                                let locdateStr = String(locdate)  // 예: "20250101"
                                if locdateStr.count == 8 {
                                    let yearStr = locdateStr.prefix(4)
                                    let monthStr = locdateStr.dropFirst(4).prefix(2)
                                    let dayStr = locdateStr.suffix(2)
                                    let formattedDate = "\(yearStr)-\(monthStr)-\(dayStr)"
                                    print("휴일: \(formattedDate) - \(dateName)")
                                    self.holidays[formattedDate] = dateName
                                }
                            }
                        }
                    } else {
                        print("JSON 파싱 실패: 'items' 또는 'item' 키가 없습니다.")
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
    
    // monthLabel은 "MMMM yyyy" 형식으로 표시 (예: February 2025)
    func updateMonthLabel() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM yyyy"
        monthLabel.text = formatter.string(from: currentDate)
    }
    
    // MARK: - UICollectionViewDataSource
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        // 요일 헤더 7개 + 날짜 42개 = 49개
        return 49
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "dayCell", for: indexPath) as! CalendarDayCell
        
        if indexPath.item < 7 {
            // 첫 번째 행: 요일 헤더
            cell.dateLabel.text = daysOfWeek[indexPath.item]
            cell.dateLabel.font = UIFont.boldSystemFont(ofSize: 14)
            cell.dateLabel.textColor = (indexPath.item == 0 ? .red : (indexPath.item == 6 ? .blue : .black))
            cell.scheduleStackView.isHidden = true
        } else {
            cell.scheduleStackView.isHidden = false
            // 현재 월의 1일 계산 (년도, 월)
            let components = calendar.dateComponents([.year, .month], from: currentDate)
            guard let firstDayOfMonth = calendar.date(from: components) else { return cell }
            
            // 1일의 요일 및 오프셋 계산 (캘린더의 firstWeekday를 고려)
            let weekday = calendar.component(.weekday, from: firstDayOfMonth)
            var offset = weekday - calendar.firstWeekday
            if offset < 0 { offset += 7 }
            
            let index = indexPath.item - 7  // 날짜 셀의 인덱스 (0 ~ 41)
            let dayNumber = index - offset + 1
            
            let currentMonthRange = calendar.range(of: .day, in: .month, for: currentDate)!
            let currentMonthDays = currentMonthRange.count
            
            var displayDate: Date?
            var textColor: UIColor = .black
            
            if dayNumber < 1 {
                // 이전 달 처리
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
                // 다음 달 처리
                let day = dayNumber - currentMonthDays
                textColor = .lightGray
                if let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentDate) {
                    var nextComponents = calendar.dateComponents([.year, .month], from: nextMonth)
                    nextComponents.day = day
                    displayDate = calendar.date(from: nextComponents)
                }
            } else {
                // 현재 달 처리
                textColor = .black
                var currentComponents = calendar.dateComponents([.year, .month], from: currentDate)
                currentComponents.day = dayNumber
                displayDate = calendar.date(from: currentComponents)
            }
            
            // displayDate가 유효하면 "MMM dd" 형식으로 날짜 표시 (예: Feb 04)
            if let displayDate = displayDate {
                let dateFormatter = DateFormatter()
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                dateFormatter.dateFormat = "MMM dd"
                cell.dateLabel.text = dateFormatter.string(from: displayDate)
            } else {
                cell.dateLabel.text = ""
            }
            cell.dateLabel.textColor = textColor
            
            // 기존 스케줄/휴일 레이블 제거
            cell.scheduleStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
            
            // 휴일 조회 – displayDate에서 하루(-1일) 오프셋 적용 후 lookup
            if let displayDate = displayDate,
               let holidayDate = calendar.date(byAdding: .day, value: +1, to: displayDate) {
                let dateFormatter = DateFormatter()
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                dateFormatter.dateFormat = "yyyy-MM-dd"
                let holidayKey = dateFormatter.string(from: holidayDate)
                if let holiday = holidays[holidayKey] {
                    let holidayLabel = UILabel()
                    holidayLabel.font = UIFont.systemFont(ofSize: 10)
                    holidayLabel.textColor = .red
                    holidayLabel.text = "🎉 \(holiday)"
                    cell.scheduleStackView.addArrangedSubview(holidayLabel)
                }
                
                // 스케줄 정보가 있다면 (추가 스케줄 데이터가 있을 경우)
                let originalDateKey = dateFormatter.string(from: displayDate)
                if let dailySchedules = schedules[originalDateKey] {
                    for schedule in dailySchedules {
                        let scheduleLabel = UILabel()
                        scheduleLabel.font = UIFont.systemFont(ofSize: 10)
                        scheduleLabel.numberOfLines = 0
                        if let workType = schedule["WorkType"], workType == "FLY" {
                            scheduleLabel.text = "✈️ \(schedule["Item"] ?? "") \n\(schedule["DepAp"] ?? "")-\(schedule["ArrAp"] ?? "")"
                        } else {
                            scheduleLabel.text = "📌 \(schedule["Activity"] ?? "")"
                        }
                        cell.scheduleStackView.addArrangedSubview(scheduleLabel)
                    }
                }
            }
        }
        return cell
    }
    
    // MARK: - UICollectionViewDelegateFlowLayout
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let flowLayout = collectionViewLayout as? UICollectionViewFlowLayout else {
            return CGSize.zero
        }
        
        let sectionInset = flowLayout.sectionInset
        let interItemSpacing = flowLayout.minimumInteritemSpacing
        // 좌우 여백과 6개의 셀 간격을 반영하여 7열의 셀 너비 계산
        let totalHorizontalSpacing = sectionInset.left + sectionInset.right + interItemSpacing * 6
        let cellWidth = (collectionView.frame.width - totalHorizontalSpacing) / 7
        
        // 첫 번째 행(요일 헤더)의 높이를 30으로 고정
        let headerRowHeight: CGFloat = 30
        if indexPath.item < 7 {
            return CGSize(width: cellWidth, height: headerRowHeight)
        } else {
            let lineSpacing = flowLayout.minimumLineSpacing
            // 나머지 42셀은 6행으로 배치:
            // 전체 컬렉션 높이에서 (sectionInset.top + sectionInset.bottom + 헤더 높이 + 5 * 행간)을 뺀 값을 6으로 나눔.
            let totalVerticalSpacing = flowLayout.sectionInset.top + flowLayout.sectionInset.bottom + headerRowHeight + lineSpacing * 5
            let availableHeight = collectionView.frame.height - totalVerticalSpacing
            let cellHeight = availableHeight / 6
            return CGSize(width: cellWidth, height: cellHeight)
        }
    }
}

// MARK: - CalendarDayCell
class CalendarDayCell: UICollectionViewCell {
    
    // 날짜 또는 요일을 표시할 레이블
    let dateLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.boldSystemFont(ofSize: 14)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // 스케줄 또는 휴일 정보를 표시할 스택뷰
    let scheduleStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 2
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.borderWidth = 0.5
        contentView.layer.borderColor = UIColor.lightGray.cgColor
        
        contentView.addSubview(dateLabel)
        contentView.addSubview(scheduleStackView)
        
        NSLayoutConstraint.activate([
            dateLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            dateLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            dateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            scheduleStackView.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 4),
            scheduleStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            scheduleStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            scheduleStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
