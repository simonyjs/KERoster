//
//  CrewListByMonthViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 10/11/25.

import UIKit

final class CrewListByMonthViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    @IBOutlet weak var tableView: UITableView!   // 스토리보드에 Table View + outlet 연결

    // 외부에서 전달
    var schedules: [String: [[String: String]]] = [:]

    // 월별 그룹: "MMM yyyy" -> 그 달에 CrewList가 있는 entry들의 배열
    private var monthBuckets: [String: [[String: String]]] = [:]
    private var sortedMonths: [String] = []

    private let schedulesUserDefaultsKey = "schedules"

    private let inputFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd-MMM-yyyy"
        return f
    }()
    private let monthFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM yyyy"
        return f
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Crew List by Month"
        view.backgroundColor = .systemBackground

        // schedules 전달이 없으면 iCloud/App Group에서 로딩
        if schedules.isEmpty {
            NSUbiquitousKeyValueStore.default.synchronize()
            if let json = NSUbiquitousKeyValueStore.default.string(forKey: "schedules_json"),
               let data = json.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String: [[String: String]]].self, from: data) {
                schedules = decoded
            } else if let shared = UserDefaults(suiteName: "group.org.duckdns.cageyjs.KERoster"),
                      let data = shared.data(forKey: schedulesUserDefaultsKey),
                      let decoded = try? JSONDecoder().decode([String: [[String: String]]].self, from: data) {
                schedules = decoded
            }
        }

        buildMonthBuckets()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        if monthBuckets.isEmpty {
            let lbl = UILabel()
            lbl.text = "저장된 CrewList가 없습니다."
            lbl.textAlignment = .center
            lbl.textColor = .secondaryLabel
            lbl.numberOfLines = 0
            tableView.backgroundView = lbl
        }
    }

    private func buildMonthBuckets() {
        monthBuckets.removeAll()

        for (dateKey, entries) in schedules {
            guard let d = inputFmt.date(from: dateKey) else { continue }
            let monthKey = monthFmt.string(from: d)
            for e in entries {
                if let json = e["CrewList"], !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    monthBuckets[monthKey, default: []].append(e)
                }
            }
        }

        // 날짜 순 정렬
        sortedMonths = monthBuckets.keys.sorted { (m1, m2) in
            guard let d1 = monthFmt.date(from: m1), let d2 = monthFmt.date(from: m2) else { return m1 < m2 }
            return d1 < d2
        }
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sortedMonths.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let monthKey = sortedMonths[indexPath.row]
        let entries = monthBuckets[monthKey] ?? []

        // 그 달의 편수(FLY/TVL만 집계), 그리고 'CrewList 인원 총합'도 계산
        var flightCount = 0
        var totalCrewMembers = 0
        for e in entries {
            let wt = e["WorkType"] ?? ""
            if wt == "FLY" || wt == "TVL" { flightCount += 1 }
            totalCrewMembers += crewCount(from: e)
        }

        let title = "🗓️ \(monthKey)"
        let subtitle = "\(flightCount) Flight(s) with CrewList\nTotal crew members saved: \(totalCrewMembers)"

        let bold = UIFont.boldSystemFont(ofSize: 18)
        let reg  = UIFont.systemFont(ofSize: 14)

        let att = NSMutableAttributedString(string: title + "\n", attributes: [.font: bold])
        att.append(NSAttributedString(string: subtitle, attributes: [.font: reg]))

        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.attributedText = att
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let monthKey = sortedMonths[indexPath.row]
        let entries = monthBuckets[monthKey] ?? []

        let sb = UIStoryboard(name: "Main", bundle: nil)
        if let vc = sb.instantiateViewController(withIdentifier: "CrewListMonthDetailViewController") as? CrewListMonthDetailViewController {
            vc.titleText = monthKey
            vc.entries = entries
            navigationController?.pushViewController(vc, animated: true)
        }
    }

    // MARK: - Helpers

    private func crewCount(from entry: [String: String]) -> Int {
        guard let json = entry["CrewList"],
              let data = json.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [[String: String]] else {
            return 0
        }
        return arr.count
    }
}

