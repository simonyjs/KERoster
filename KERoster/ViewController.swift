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
        case 2:
            print("Option 3 selected")
        case 3:
            print("Option 4 selected")
        case 4:
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
}





