//
//  ViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/01/22.
//

import UIKit
import WebKit
import SwiftSoup

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    @IBOutlet weak var webView: WKWebView!
    @IBOutlet weak var segmentedControl: UISegmentedControl!
    var schedules: [String: [String: String]] = [:]
    @IBOutlet weak var scheduleStackView: UIStackView! // 스택 뷰 연결
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // WebView delegate 설정
        webView.navigationDelegate = self
        webView.uiDelegate = self
        
        // 초기 URL 로드
        loadURL("https://iflightke.ibsplc.aero/iflight-cwp/web/loginpage")
        
        // 세그먼트 컨트롤 초기 설정
        segmentedControl.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)
    }

    // 세그먼트 변경 이벤트 처리
    @objc func segmentChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            loadURL("https://iflightke.ibsplc.aero/iflight-cwp/web/getMainPage")
        case 1:
            loadURL("https://crewlink.koreanair.com/")
        case 2:// Import schedule
            print(schedules)
            importSchedule()
        case 3:// View schedule
            print("Option 4 selected")
        case 4:// View Duty
            print("Option 5 selected")
        default:
            print("Invalid selection")
        }
    }

    // 주어진 URL을 웹뷰에 로드하는 함수
    func loadURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }

    // 링크 클릭 시 현재 WebView에서 열리도록 설정
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated {
            print("클릭된 URL: \(navigationAction.request.url?.absoluteString ?? "알 수 없음")")
        }
        decisionHandler(.allow)
    }

    // 새 창 열기 방지
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        webView.load(navigationAction.request)
        return nil
    }
    // 스케줄을 가져오는 함수 지정
    func importSchedule() {
        webView.evaluateJavaScript("document.documentElement.outerHTML.toString()") { [weak self] (html: Any?, error: Error?) in
            guard let self = self else { return }
            if let htmlContent = html as? String {
                do {
                    let doc: Document = try SwiftSoup.parse(htmlContent)
                    let rows: Elements = try doc.select("tr")
                    self.schedules.removeAll() // Clear previous schedules if any

                    for row in rows {
                        let columns: Elements = try row.select("td")
                        if columns.count > 1 {
                            let date = try columns[1].text() // Adjust index as per column layout
                            let activity = try columns[2].text()
                            self.schedules[date] = ["activity": activity]
                        }
                    }

                    // Log the parsed schedules in date order
                    let sortedSchedules = self.schedules.sorted { $0.key < $1.key }
                    for (date, details) in sortedSchedules {
                        print("\(date): \(details)")
                    }
                } catch Exception.Error(let type, let message) {
                    print("Error: \(type) - \(message)")
                } catch {
                    print("Error: \(error.localizedDescription)")
                }
            } else {
                print("Failed to retrieve HTML content: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }



    // 스케줄 추가 메서드
    func addScheduleToStackView(date: String, activity: String) {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false

        let dateLabel = UILabel()
        dateLabel.text = date
        dateLabel.font = UIFont.boldSystemFont(ofSize: 16)
        dateLabel.translatesAutoresizingMaskIntoConstraints = false

        let activityLabel = UILabel()
        activityLabel.text = activity
        activityLabel.font = UIFont.systemFont(ofSize: 14)
        activityLabel.textColor = .gray
        activityLabel.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(dateLabel)
        containerView.addSubview(activityLabel)

        NSLayoutConstraint.activate([
            dateLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            dateLabel.topAnchor.constraint(equalTo: containerView.topAnchor),

            activityLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            activityLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 4),
            activityLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        scheduleStackView.addArrangedSubview(containerView)
    }

}
