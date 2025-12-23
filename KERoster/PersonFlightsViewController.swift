//
//  PersonFlightsViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 10/19/25.
//
//  선택한 사람의 비행(FLY/TVL) 리스트를 날짜순으로 표시
//  - FLY/TVL: 기존 표시 유지
//  - 그 외: Other(s) 섹션으로 분리
//  - 플라이트 넘버: Item/Activity 우선 + 정규식 폴백
//  - 워크타입 배지([FLY]/[TVL]) 표시
//  - DH 접두어 제거
//

import UIKit

final class PersonFlightsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    @IBOutlet weak var tableView: UITableView!

    struct Person {
        let name: String
        let id: String
    }
    struct FlightRef {
        let dateKey: String   // "dd-MMM-yyyy"
        let entry: [String: String]
    }

    // 상위 VC에서 주입
    var person: Person!
    var flights: [FlightRef] = []
    var inputFmt: DateFormatter!   // "dd-MMM-yyyy"

    private let dateOutFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd (EEE)"
        return f
    }()

    // 분리된 데이터
    private var flightRefs: [FlightRef] = []     // FLY/TVL
    private var otherRefs: [FlightRef] = []      // 나머지

    private let flightWT: Set<String> = ["FLY","TVL"]
    private func normWT(_ entry: [String:String]) -> String {
        (entry["WorkType"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
    private func isFlightEntry(_ entry: [String:String]) -> Bool {
        flightWT.contains(normWT(entry))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // 안전장치 (혹시 inputFmt 주입 누락 시)
        if inputFmt == nil {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "dd-MMM-yyyy"
            inputFmt = f
        }

        let titleStr = person.id == "—" ? person.name : "\(person.name) (\(person.id))"
        title = titleStr
        view.backgroundColor = .systemBackground

        // 날짜 최근날짜 순 정렬 (전체)
        flights.sort { lhs, rhs in
            guard let d1 = inputFmt.date(from: lhs.dateKey),
                  let d2 = inputFmt.date(from: rhs.dateKey) else { return lhs.dateKey < rhs.dateKey }
            return d1 > d2
        }

        // FLY/TVL vs Other(s) 분리
        flightRefs = flights.filter { isFlightEntry($0.entry) }
        otherRefs  = flights.filter { !isFlightEntry($0.entry) }

        // 각 섹션 내부도 날짜 최근순 유지
        flightRefs.sort { lhs, rhs in
            guard let d1 = inputFmt.date(from: lhs.dateKey),
                  let d2 = inputFmt.date(from: rhs.dateKey) else { return lhs.dateKey < rhs.dateKey }
            return d1 > d2
        }
        otherRefs.sort { lhs, rhs in
            guard let d1 = inputFmt.date(from: lhs.dateKey),
                  let d2 = inputFmt.date(from: rhs.dateKey) else { return lhs.dateKey < rhs.dateKey }
            return d1 > d2
        }

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        if flightRefs.isEmpty && otherRefs.isEmpty {
            let lbl = UILabel()
            lbl.text = "NO FLT RECORD."
            lbl.textAlignment = .center
            lbl.textColor = .secondaryLabel
            lbl.numberOfLines = 0
            tableView.backgroundView = lbl
        } else {
            tableView.backgroundView = nil
        }
    }

    // MARK: - UITableViewDataSource
    func numberOfSections(in tableView: UITableView) -> Int {
        // other가 있으면 2섹션, 없으면 Flights만
        return otherRefs.isEmpty ? 1 : 2
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 { return "Flights" }
        return "Other(s)"
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return flightRefs.count }
        return otherRefs.count
    }

    private func ref(for indexPath: IndexPath) -> FlightRef {
        if indexPath.section == 0 { return flightRefs[indexPath.row] }
        return otherRefs[indexPath.row]
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let refItem = ref(for: indexPath)
        let e = refItem.entry

        let dateStr: String = {
            if let d = inputFmt.date(from: refItem.dateKey) { return dateOutFmt.string(from: d) }
            return refItem.dateKey
        }()

        let isFlight = (indexPath.section == 0)

        // 표시용 제목: 날짜 • (FlightNo or Activity/Item) • [TAG]
        let mainTitle: String = {
            if isFlight {
                return displayFlightNo(from: e)
            } else {
                return displayOtherTitle(from: e)
            }
        }()

        var title = "\(dateStr)  •  \(mainTitle)"

        if isFlight {
            if let wt = workTypeTag(from: e) { title += "  [\(wt)]" }   // 기존 유지
        } else {
            title += "  [OTHER]"  // Other(s)로 통일
        }

        // 표시용 서브타이틀
        let subtitle = routeTimeSummary(from: e)

        let bold = UIFont.boldSystemFont(ofSize: 16)
        let reg  = UIFont.systemFont(ofSize: 14)

        let att = NSMutableAttributedString(string: title + "\n", attributes: [.font: bold])
        att.append(NSAttributedString(string: subtitle, attributes: [.font: reg]))

        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.attributedText = att
        cell.selectionStyle = .none
        return cell
    }

    // MARK: - Helpers

    // Other(s) 표시용 타이틀: Activity 우선, 없으면 Item, 없으면 WorkType
    private func displayOtherTitle(from e: [String:String]) -> String {
        let candidates = ["Activity", "Item", "WorkType"]
        for k in candidates {
            if let v = e[k]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                return v
            }
        }
        return "OTHER"
    }

    // 키 정규화: 영숫자만 남기고 소문자
    private func normalizeKey(_ s: String) -> String {
        s.replacingOccurrences(of: "[^A-Za-z0-9]", with: "", options: .regularExpression).lowercased()
    }

    // 키 후보 배열 중 첫 번째 유효값 반환
    private func firstValue(in dict: [String:String], keys: [String]) -> String? {
        let normMap: [String: String] = Dictionary(uniqueKeysWithValues: dict.map { (normalizeKey($0.key), $0.value) })
        for k in keys {
            let nk = normalizeKey(k)
            if let v = normMap[nk]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                return v
            }
        }
        return nil
    }

    // 텍스트에서 항공편 번호 추출 (예: KE081, KE 81, OZ1234, DL901A)
    private func extractFlightNo(from text: String) -> String? {
        let pattern = "(?i)\\b([A-Z]{2,3})\\s*(\\d{1,4}[A-Z]?)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return nil }

        // 1순위: KE*, 2순위: 첫 매치
        if let ke = matches.first(where: { ns.substring(with: $0.range(at: 1)).uppercased() == "KE" }) {
            return ns.substring(with: ke.range(at: 1)).uppercased() + ns.substring(with: ke.range(at: 2))
        }
        let m = matches[0]
        return ns.substring(with: m.range(at: 1)).uppercased() + ns.substring(with: m.range(at: 2))
    }

    // “표시용” 플라이트 넘버 (DH 접두 제거)
    private func displayFlightNo(from e: [String:String]) -> String {
        // 저장 로직 기준으로 Item/Activity 우선
        let candidateKeys = [
            "Item","Activity",
            "FlightNo","Flight No","FlightNumber","Flight Number",
            "FLTNO","FLT NO","FltNo","Flt No","FltNum","Flt Nbr","FLT"
        ]

        if let raw = firstValue(in: e, keys: candidateKeys),
           let fx = extractFlightNo(from: raw) {
            return fx
        }

        // 값들 전체에서 폴백 스캔
        for v in e.values {
            if let fx = extractFlightNo(from: v) {
                return fx
            }
        }

        // 그래도 없으면 워크타입 또는 공백
        let workType = (e["WorkType"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return workType.isEmpty ? " " : workType
    }

    // 워크타입 배지 텍스트
    private func workTypeTag(from e: [String:String]) -> String? {
        let wt = (e["WorkType"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return wt.isEmpty ? nil : wt.uppercased()
    }

    // 저장 로직 키 반영: DepAp/ArrAp + DepStnTime/ArrStnTime 우선
    private func routeTimeSummary(from e: [String:String]) -> String {
        let depAP = firstValue(in: e, keys: ["DepAp","DepAP","From","FROM","Departure","DEP"])
        let arrAP = firstValue(in: e, keys: ["ArrAp","ArrAP","To","TO","Arrival","ARR"])
        let depT  = firstValue(in: e, keys: ["DepStnTime","STD","OffBlock","ETD","Report","DutyReport"])
        let arrT  = firstValue(in: e, keys: ["ArrStnTime","STA","OnBlock","ETA","Debrief","DutyDebrief"])

        var parts: [String] = []
        if let d = depAP, let a = arrAP, !d.isEmpty, !a.isEmpty { parts.append("\(d) → \(a)") }
        if let dt = depT, let at = arrT, !dt.isEmpty, !at.isEmpty { parts.append("\(dt) ~ \(at)") }

        if parts.isEmpty { parts.append(e["WorkType"] ?? "") }
        return parts.joined(separator: "   •   ")
    }
}
