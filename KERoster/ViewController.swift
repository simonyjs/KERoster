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
    var schedules: [String: [String: String]] = [:]
    var toolbar: UIToolbar!
    @IBOutlet weak var scheduleStackView: UIStackView! // 스택 뷰 연결
    // 첫 번째 UIBarButtonItem을 IBAction으로 연결
    @IBAction func iflightButtonTapped(_ sender: UIBarButtonItem) {
        loadURL("https://iflightke.ibsplc.aero/iflight-cwp/")
    }
    // 두 번째 UIBarButtonItem을 IBAction으로 연결
    @IBAction func CrewLinkButtonTapped(_ sender: UIBarButtonItem) {
        loadURL("https://crewlink.koreanair.com/")
    }
    // 세 번째 UIBarButtonItem을 IBAction으로 연결
    @IBAction func ImportButtonTapped(_ sender: UIBarButtonItem) {
        importSchedule()
        print(schedules)
    }
    // 네 번째 UIBarButtonItem을 IBAction으로 연결
    @IBAction func ViewListButtonTapped(_ sender: UIBarButtonItem) {
        print("ViewList")
    }
    // 다섯 번째 UIBarButtonItem을 IBAction으로 연결
    @IBAction func PrintButtonTapped(_ sender: UIBarButtonItem) {
        print("Print")
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // WebView delegate 설정
        webView.navigationDelegate = self
        webView.uiDelegate = self
        
        loadURL("https://iflightke.ibsplc.aero/iflight-cwp/web/loginpage")
    }
    // 링크 클릭 시 현재 WebView에서 열리도록 설정
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil {
            // 새 창을 열려고 하면 현재 웹뷰에서 로드
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    // 새 창 열기 방지 및 현재 WebView에서 열도록 설정
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    // URL을 WebView에 로드하는 함수
    func loadURL(_ urlString: String) {
        print("loadURL 호출됨: \(urlString)") // 디버깅용 로그
        if let url = URL(string: urlString) {
            let request = URLRequest(url: url)
            webView.load(request)
        } else {
            print("잘못된 URL 형식: \(urlString)")
        }
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
