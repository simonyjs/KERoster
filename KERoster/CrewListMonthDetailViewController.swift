//
//  CrewListMonthDetailViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 10/11/25.
//

import UIKit

final class CrewListMonthDetailViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    @IBOutlet weak var tableView: UITableView!

    var titleText: String = ""
    var entries: [[String: String]] = []   // 해당 월의 CrewList 있는 엔트리들

    override func viewDidLoad() {
        super.viewDidLoad()
        title = titleText
        view.backgroundColor = .systemBackground

        // 보기 좋게 정렬: 날짜+출발시각 기준
        entries.sort { lhs, rhs in
            let l = (lhs["DepDate"] ?? lhs["Date"] ?? "") + " " + (lhs["DepStnTime"] ?? "00:00")
            let r = (rhs["DepDate"] ?? rhs["Date"] ?? "") + " " + (rhs["DepStnTime"] ?? "00:00")
            return l < r
        }

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let e = entries[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)

        let item = e["Item"] ?? ""
        let dep = e["DepAp"] ?? ""
        let arr = e["ArrAp"] ?? ""
        let depT = e["DepStnTime"] ?? ""
        let arrT = e["ArrStnTime"] ?? ""
        let d    = e["DepDate"] ?? e["Date"] ?? ""
        let count = crewCount(from: e)

        let title = "\(item)  \(depT) \(dep) → \(arr) \(arrT)"
        let subtitle = "\(d)   •  Crew Members : \(count)"

        let bold = UIFont.boldSystemFont(ofSize: 16)
        let reg  = UIFont.systemFont(ofSize: 14)
        let att = NSMutableAttributedString(string: title + "\n", attributes: [.font: bold])
        att.append(NSAttributedString(string: subtitle, attributes: [.font: reg]))

        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.attributedText = att
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let e = entries[indexPath.row]
        let vc = CrewListFlightDetailViewController()
        vc.entry = e
        navigationController?.pushViewController(vc, animated: true)
    }

    // MARK: - Helpers

    private func crewCount(from entry: [String: String]) -> Int {
        guard let json = entry["CrewList"],
              let data = json.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [[String: String]] else { return 0 }
        return arr.count
    }
}

