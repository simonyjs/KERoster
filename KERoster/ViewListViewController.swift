//
//  ViewListViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/01/30.
//

import UIKit

class ViewListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    @IBOutlet weak var tableView: UITableView! // 스토리보드에서 연결한 테이블뷰
    
    var schedules: [String: [[String: String]]] = [:] // ✅ 날짜별 여러 개의 스케줄을 저장하도록 수정
    var sortedDates: [String] = [] // 정렬된 날짜 리스트

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Schedule List"
        view.backgroundColor = .white
        
        // ✅ 데이터 확인용 로그 출력
        print("📌 전달된 schedules 데이터: \(schedules)")

        // ✅ 날짜 형식 맞춤 (현재 "19-Jan-2025" 같은 형식 사용 중)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-MMM-yyyy"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        // ✅ 날짜를 변환하여 정렬 (변환 실패 시 기본 문자열 정렬)
        sortedDates = schedules.keys.sorted {
            guard let date1 = dateFormatter.date(from: $0),
                  let date2 = dateFormatter.date(from: $1) else {
                return $0 < $1 // 변환 실패 시 문자열 정렬 적용
            }
            return date1 < date2 // 날짜 객체를 비교하여 정렬
        }
        
        // ✅ 테이블 뷰 설정
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData() // ✅ 화면 갱신 시 테이블 뷰 업데이트
    }
    
    // MARK: - UITableViewDataSource
    
    // ✅ 각 날짜별 스케줄 개수만큼 행(Row) 개수를 설정
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sortedDates.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let date = sortedDates[indexPath.row]
        
        // ✅ 여러 개의 스케줄이 있을 경우, 순번을 포함해 출력
        if let scheduleList = schedules[date] {
            let scheduleText = scheduleList.map { schedule in
                let seq = schedule["Seq"] ?? "1"
                let activity = schedule["Activity"] ?? "스케줄 없음"
                let workType = schedule["WorkType"] ?? "" // ✅ 오류 원인: 이 변수가 사용되지 않음
                let item = schedule["Item"] ?? ""

                // ✅ workType이 "FLY" 또는 "TVL"인 경우에만 표시하도록 수정
                if workType == "FLY" || workType == "TVL" {
                    return "🔢 \(seq) | 📅 \(date) - ✈️ \(item) (\(workType))"
                } else {
                    return "🔢 \(seq) | 📅 \(date) - 🏢 \(activity)"
                }
            }.joined(separator: "\n")

            cell.textLabel?.text = scheduleText
            cell.textLabel?.numberOfLines = 0 // ✅ 여러 줄 출력 가능하도록 설정
        } else {
            cell.textLabel?.text = "📅 \(date) - 스케줄 없음"
        }

        cell.accessoryType = .disclosureIndicator // 상세 페이지 이동을 위한 표시
        
        return cell
    }

    
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let selectedDate = sortedDates[indexPath.row]
        let details = schedules[selectedDate] ?? []
        
        // ✅ 상세 정보를 보여줄 새로운 ViewController로 이동
        let detailVC = ScheduleDetailViewController()
        detailVC.scheduleDetailsList = details // ✅ 배열 형태로 전달
        detailVC.selectedDate = selectedDate
        navigationController?.pushViewController(detailVC, animated: true)
    }
}
