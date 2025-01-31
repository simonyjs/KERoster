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
    var sortedDates: [String] = [] // ✅ DepDate 기준으로 정렬된 날짜 리스트

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Schedule List"
        view.backgroundColor = .white
        
        // ✅ 데이터 확인용 로그 출력
        print("📌 전달된 schedules 데이터: \(schedules)")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        // ✅ DepDate 기준으로 날짜 정렬
        sortedDates = schedules.keys.sorted {
            let depDate1 = schedules[$0]?.first?["DepDate"] ?? $0
            let depDate2 = schedules[$1]?.first?["DepDate"] ?? $1
            
            guard let date1 = dateFormatter.date(from: depDate1),
                  let date2 = dateFormatter.date(from: depDate2) else {
                return depDate1 < depDate2 // 날짜 변환 실패 시 문자열 비교
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
                let depDate = schedule["DepDate"] ?? date // ✅ DepDate 사용
                let activity = schedule["Activity"] ?? "NONE"
                let workType = schedule["WorkType"] ?? ""
                let item = schedule["Item"] ?? ""
                let depStnTime = schedule["DepStnTime"] ?? ""
                let arrStnTime = schedule["ArrStnTime"] ?? ""
                let depAp = schedule["DepAp"] ?? ""
                let arrAp = schedule["ArrAp"] ?? ""
                let dutyReport = schedule["DutyReport"] ?? ""
                let dutyDebrief = schedule["DutyDebrief"] ?? ""

                // ✅ workType이 "FLY" 또는 "TVL"인 경우에만 표시하도록 수정
                if workType == "FLY" || workType == "TVL" {
                    var modifiedItem = item
                    var transportIcon = "✈️" // 기본값: FLY → ✈️

                    if workType == "TVL" {
                        transportIcon = "💺" // ✅ TVL → 💺 아이콘 변경
                        if !item.isEmpty {
                            modifiedItem = "DH" + item.dropFirst(2) // ✅ 앞 두 글자를 "DH"로 변경
                        }
                    }

                    return "🔢 \(seq) | 📅 \(depDate) - \(transportIcon) \(modifiedItem) \(depStnTime) \(depAp) - \(arrAp) \(arrStnTime) (\(workType))"
                }
                // ✅ DO(휴식)인 경우 HOME 이모지로 변경
                else if activity == "DO" {
                    return "🔢 \(seq) | 📅 \(depDate) - 🏠 \(activity) \(dutyReport) - \(dutyDebrief)"
                }
                // ✅ 기본값 (그 외 모든 활동)
                else {
                    return "🔢 \(seq) | 📅 \(depDate) - 🏢 \(activity) \(dutyReport) - \(dutyDebrief)"
                }

            }.joined(separator: "\n")

            cell.textLabel?.text = scheduleText
            cell.textLabel?.numberOfLines = 0 // ✅ 여러 줄 출력 가능하도록 설정
        } else {
            cell.textLabel?.text = "📅 \(date) - NONE"
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


