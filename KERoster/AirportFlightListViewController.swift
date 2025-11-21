//
//  AirportFlightListViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 11/21/25.
//

import UIKit

class AirportFlightListViewController: UITableViewController {
    
    var airportCode: String = ""
    var airportName: String?
    var flights: [AirportFlightRef] = []
    
    // MARK: - DateFormatter (입력: dd-MMM-yyyy → 출력: yyyy-MM-dd)
    private lazy var inDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "dd-MMM-yyyy"
        return df
    }()
    
    private lazy var outDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
    
    /// "31-Oct-2025" → "2025-10-31"
    private func formattedDate(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let d = inDateFormatter.date(from: trimmed) {
            return outDateFormatter.string(from: d)
        }
        // 파싱 실패시 원본 그대로
        return trimmed
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let name = airportName, !name.isEmpty {
            title = "\(airportCode) – \(name)"
        } else {
            title = airportCode
        }
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FlightCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
    }
    
    // MARK: - TableView DataSource
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView,
                            numberOfRowsInSection section: Int) -> Int {
        return flights.count
    }
    
    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FlightCell", for: indexPath)
        let ref = flights[indexPath.row]
        let e = ref.entry
        
        // 원본 날짜 문자열 (DepDate 우선, 없으면 Date, 그것도 없으면 bucket key)
        let rawDate = e["DepDate"] ?? e["Date"] ?? ref.dateKey
        // "2025-10-31" 형식으로 변환
        let date = formattedDate(rawDate)
        
        let item = e["Item"] ?? e["Activity"] ?? ""
        let workType = (e["WorkType"] ?? "").uppercased()
        
        let depAp = e["DepAp"] ?? ""
        let depTime = e["DepStnTime"] ?? ""
        let arrAp = e["ArrAp"] ?? ""
        let arrTime = e["ArrStnTime"] ?? ""
        
        let fh = e["FlyingHours"] ?? ""
        let dh = e["DutyHours"] ?? ""
        
        // 이 공항이 Dep인지 Arr인지 표시
        var role = ""
        if depAp == airportCode && arrAp == airportCode {
            role = "(DEP/ARR)"
        } else if depAp == airportCode {
            role = "(DEP)"
        } else if arrAp == airportCode {
            role = "(ARR)"
        }
        
        var lines: [String] = []
        
        // 1줄: 날짜 + 편명 + WT + (DEP/ARR)
        lines.append("\(date)  \(item)  [\(workType)] \(role)")
        
        // 2줄: 노선/시간
        if !depAp.isEmpty || !arrAp.isEmpty {
            lines.append("\(depAp) \(depTime)  →  \(arrAp) \(arrTime) ||| Flight Hours : \(fh)")
        }
        
        // 3줄: 크루 이름 + ID 요약 한 줄
        let crewLines = buildCrewSummaryLines(from: e)
        if !crewLines.isEmpty {
            lines.append(contentsOf: crewLines)   // 여기서 보통 1줄만 추가됨 (3번째 줄)
        } else {
            // CrewList 없고 FH/DH 정보만 있는 경우, 한 줄이라도 보여주기
            var extra: [String] = []
            if !fh.isEmpty { extra.append("FH \(fh)") }
            if !dh.isEmpty { extra.append("DH \(dh)") }
            if !extra.isEmpty {
                lines.append(extra.joined(separator: " | "))
            }
        }
        
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.font = .systemFont(ofSize: 14)
        cell.textLabel?.text = lines.joined(separator: "\n")
        
        return cell
    }
    
    // 디테일 Alert 화면은 필요 없다고 하셨으니, didSelect는 비워둡니다.
    override func tableView(_ tableView: UITableView,
                            didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        // 아무 동작 없음 (요약 화면만 사용)
    }
    
    // MARK: - CrewList → "이름 아이디" 한 줄 요약
    private func buildCrewSummaryLines(from entry: [String:String]) -> [String] {
        guard let json = entry["CrewList"],
              let data = json.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [[String:String]],
              !arr.isEmpty else {
            return []
        }
        
        // 각 크루를 "이름 (ID)" 형식으로 만들어 한 줄에 합치기
        var crewParts: [String] = []
        for row in arr {
            let name = (row["Name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let crewID = (row["CrewID"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }
            
            if crewID.isEmpty {
                crewParts.append(name)
            } else {
                crewParts.append("\(name) (\(crewID))")
            }
        }
        
        guard !crewParts.isEmpty else { return [] }
        
        // 예: "• Hong (123456) | Kim (654321)"
        let line = "• " + crewParts.joined(separator: " | ")
        return [line]
    }
}
