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
    
    private func formattedDate(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return "" }
        return inDateFormatter.date(from: raw)
            .map { outDateFormatter.string(from: $0) } ?? raw
    }
    // 구분선 추가
    private func fullWidthSeparator() -> String {
        let font = UIFont.systemFont(ofSize: 12)
        let char = "─" as NSString
        let charWidth = char.size(withAttributes: [.font: font]).width
        
        let screenWidth = UIScreen.main.bounds.width - 32   // 좌우 여백 고려
        let count = Int(screenWidth / charWidth)
        
        return String(repeating: "─", count: max(count, 5))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let name = airportName, !name.isEmpty {
            title = "\(airportCode) – \(name)"
        } else {
            title = airportCode
        }
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FlightCell")
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 140
        tableView.backgroundColor = .systemBackground
    }
    
    // MARK: - TableView
    
    override func tableView(_ tableView: UITableView,
                            numberOfRowsInSection section: Int) -> Int {
        flights.count
    }
    
    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "FlightCell", for: indexPath)
        let ref = flights[indexPath.row]
        
        let attr = buildFlightSummary(e: ref.entry, dateKey: ref.dateKey, isLast: indexPath.row == flights.count - 1)
        
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.attributedText = attr
        cell.backgroundColor = .systemBackground
        
        return cell
    }
    
    
    // MARK: - 메인 요약 생성
    
    private func buildFlightSummary(e: [String:String], dateKey: String, isLast: Bool) -> NSAttributedString {
        let attr = NSMutableAttributedString()
        
        // -----------------------------
        // 1) 날짜/편명/WorkType/역할
        // -----------------------------
        let rawDate = e["DepDate"] ?? e["Date"] ?? dateKey
        let dateStr = formattedDate(rawDate)
        
        let item = (e["Item"] ?? e["Activity"] ?? "").trimmed
        let workType = (e["WorkType"] ?? "").uppercased().trimmed
        
        let depAp = (e["DepAp"] ?? "").trimmed
        let arrAp = (e["ArrAp"] ?? "").trimmed
        let depTime = (e["DepStnTime"] ?? "").trimmed
        let arrTime = (e["ArrStnTime"] ?? "").trimmed
        
        // 공항 역할 표시
        let role: String = {
            switch (depAp == airportCode, arrAp == airportCode) {
            case (true, true): return "(DEP/ARR)"
            case (true, false): return "(DEP)"
            case (false, true): return "(ARR)"
            default: return ""
            }
        }()
        
        // WT 배지 색상
        let wtColor: UIColor = {
            switch workType {
            case "FLY": return .systemBlue
            case "TVL": return .systemGreen
            default: return .secondaryLabel
            }
        }()
        
        // 날짜 + 편명
        attr.append(string: "\(dateStr)   \(item)   ", font: .boldSystemFont(ofSize: 17))
        
        // WT가 있을 때만
        if !workType.isEmpty {
            attr.append(string: "[\(workType)]  ",
                        font: .boldSystemFont(ofSize: 15),
                        color: wtColor)
        }
        
        // 역할 추가
        if !role.isEmpty {
            attr.append(string: "\(role)\n", font: .systemFont(ofSize: 14), color: .secondaryLabel)
        } else {
            attr.append(string: "\n")
        }
        
        // -----------------------------
        // 2) 노선
        // -----------------------------
        if !depAp.isEmpty || !arrAp.isEmpty {
            attr.append(string: "\(depAp) \(depTime)  →  \(arrAp) \(arrTime)\n",
                        font: .boldSystemFont(ofSize: 15))
        }
        
        // -----------------------------
        // 3) FH
        // -----------------------------
        let fh = (e["FlyingHours"] ?? "").trimmed
        if !fh.isEmpty {
            attr.append(string: "Flight Hours: \(fh)\n",
                        font: .systemFont(ofSize: 14),
                        color: .secondaryLabel)
        }
        
        // -----------------------------
        // 4) Crew 박스
        // -----------------------------
        let crewLines = buildCrewLines(from: e)
        if !crewLines.isEmpty {
            attr.append(string: "Crew\n",
                        font: .boldSystemFont(ofSize: 14),
                        color: .systemBlue)
            
            attr.append(string: boxLines(crewLines),
                        font: .systemFont(ofSize: 14),
                        color: .label)
        }

        // -----------------------------
        // 5) 구분선 (모든 셀 동일하게)
        // -----------------------------
        attr.append(string: fullWidthSeparator(),
                    font: .systemFont(ofSize: 12),
                    color: .tertiaryLabel)
        return attr
    }
    
    
    // MARK: - CrewList 파싱 + PIC Code(P1, P2 등)
    
    private func buildCrewLines(from entry: [String:String]) -> [String] {
        guard let json = entry["CrewList"],
              let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String:String]],
              !arr.isEmpty else { return [] }
        
        return arr.compactMap { row in
            let name = (row["Name"] ?? "").trimmed
            let id = (row["CrewID"] ?? "").trimmed
            let pic = (row["PICCode"] ?? row["Position"] ?? "").trimmed   // P1, F1
            
            guard !name.isEmpty else { return nil }
            
            var result = "• \(name)"
            if !id.isEmpty { result += " (\(id))" }
            if !pic.isEmpty { result += " [\(pic)]" }
            
            return result
        }
    }
    
    
    // MARK: - Crew 박스 스타일
    
    private func boxLines(_ lines: [String]) -> String {
        return lines.map { $0 }.joined(separator: "\n") + "\n"
    }
}


// MARK: - Extensions

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private extension NSMutableAttributedString {
    
    func append(string: String,
                font: UIFont? = nil,
                color: UIColor? = nil) {
        
        var attrs: [NSAttributedString.Key:Any] = [:]
        if let font = font { attrs[.font] = font }
        if let color = color { attrs[.foregroundColor] = color }
        
        self.append(NSAttributedString(string: string, attributes: attrs))
    }
}
