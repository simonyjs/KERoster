//
//  ViewListViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/01/30.
//

import UIKit

class ViewListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    @IBOutlet weak var tableView: UITableView! // 스토리보드에서 연결한 테이블뷰
    
    var schedules: [String: [String: String]] = [:] // 스케줄 데이터
    var sortedDates: [String] = [] // 정렬된 날짜 리스트

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Schedule List"
        view.backgroundColor = .white
        
        // ✅ 데이터 확인용 로그 출력
        print("📌 전달된 schedules 데이터: \(schedules)")
        
        // ✅ 날짜 정렬 개선 (올바른 날짜 형식으로 정렬)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        sortedDates = schedules.keys.sorted {
            guard let date1 = dateFormatter.date(from: $0),
                  let date2 = dateFormatter.date(from: $1) else { return false }
            return date1 < date2
        }
        
        // ✅ 테이블뷰 설정
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData() // ✅ 화면 갱신 시 테이블 뷰 업데이트
    }
    
    // MARK: - UITableViewDataSource
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sortedDates.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let date = sortedDates[indexPath.row]
        
        // ✅ Activity 가져오기 (없으면 "스케줄 없음")
        let activity = schedules[date]?["Activity"] ?? "스케줄 없음"
        
        // ✅ WorkType 가져오기
        let workType = schedules[date]?["WorkType"] ?? ""
        
        // ✅ Item 가져오기 (WorkType이 "FLY" 또는 "TVL"인 경우만 표시)
        let item = (workType == "FLY" || workType == "TVL") ? (schedules[date]?["Item"] ?? "") : ""
        
        // ✅ 셀 텍스트 설정
        if item.isEmpty {
            cell.textLabel?.text = "📅 \(date) - 🏢 \(activity)"
        } else {
            cell.textLabel?.text = "📅 \(date) - ✈️ \(item)"
        }
        
        cell.accessoryType = .disclosureIndicator // 상세 페이지 이동을 위한 표시
        
        return cell
    }
    
    // MARK: - UITableViewDelegate
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let selectedDate = sortedDates[indexPath.row]
        let details = schedules[selectedDate] ?? [:]
        
        // ✅ 상세 정보를 보여줄 새로운 ViewController로 이동
        let detailVC = ScheduleDetailViewController()
        detailVC.scheduleDetails = details
        detailVC.selectedDate = selectedDate
        navigationController?.pushViewController(detailVC, animated: true)
    }
}
