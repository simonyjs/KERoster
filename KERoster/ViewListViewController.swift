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
        
        // 날짜 정렬
        sortedDates = schedules.keys.sorted()
        
        // 테이블뷰 설정
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }
    
    // MARK: - UITableViewDataSource
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sortedDates.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let date = sortedDates[indexPath.row]
        let activity = schedules[date]?["activity"] ?? "정보 없음"
        cell.textLabel?.text = "\(date): \(activity)"
        return cell
    }
    
    // MARK: - UITableViewDelegate
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
