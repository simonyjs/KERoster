//
//  ViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/01/22.
//

import UIKit
import WebKit

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    @IBOutlet weak var webView: WKWebView!
    var segmentedControl: UISegmentedControl!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // WebView delegate 설정
        webView.navigationDelegate = self
        webView.uiDelegate = self
        
        // 초기 URL 로드
        loadURL("https://iflightke.ibsplc.aero/iflight-cwp/web/loginpage")
        
        // WebView에 Auto Layout 적용
        setupWebViewConstraints()
        
        // 세그먼트 컨트롤 설정
        setupSegmentedControl()
    }
    
    // WebView Auto Layout 설정
    func setupWebViewConstraints() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        
        // Safe Area 내에서 마진을 설정하여 웹뷰가 꽉 차도록 함
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60) // 세그먼트 컨트롤을 위해 웹뷰 아래에 공간을 남김
        ])
    }

    // 세그먼트 컨트롤 Auto Layout 설정
    func setupSegmentedControl() {
        // 세그먼트 컨트롤 초기화
        segmentedControl = UISegmentedControl(items: ["iflight", "CrewLink", "Option 3", "Option 4"])
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.backgroundColor = .white
        segmentedControl.selectedSegmentTintColor = .systemBlue
        segmentedControl.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)
        view.addSubview(segmentedControl)
        
        // 세그먼트 컨트롤 Auto Layout 설정
        NSLayoutConstraint.activate([
            segmentedControl.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            segmentedControl.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            segmentedControl.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    // 세그먼트 변경 시 호출되는 메서드
    @objc func segmentChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            // "iflight" 버튼이 클릭된 경우
            loadURL("https://iflightke.ibsplc.aero/iflight-cwp/web/getMainPage")
        case 1:
            // "Crewlink" 버튼이 클릭된 경우
            loadURL("https://crewlink.koreanair.com/")
            // 필요에 따라 다른 URL 로 이동
        case 2:
            // "Option 3" 버튼이 클릭된 경우
            print("Option 3 selected")
            // 필요에 따라 다른 URL 로 이동
        case 3:
            // "Option 4" 버튼이 클릭된 경우
            print("Option 4 selected")
            // 필요에 따라 다른 URL 로 이동
        default:
            break
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
}




