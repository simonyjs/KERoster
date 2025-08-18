//
//  PopupWebViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/02/18.
//

import UIKit
import WebKit

final class PopupWebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {

    static weak var current: PopupWebViewController?

    var webView: WKWebView!
    var initialRequest: URLRequest?

    override func viewDidLoad() {
        super.viewDidLoad()
        Self.current = self
        view.backgroundColor = .systemBackground

        // 네비게이션
        navigationItem.title = "Popup"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Close", style: .done, target: self, action: #selector(closeTapped))

        // WebView
        let cfg = WKWebViewConfiguration()
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: .zero, configuration: cfg)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentInset = .zero
        webView.scrollView.scrollIndicatorInsets = .zero

        // ▼ 하단 여백 제거: 화면 하단까지 제약( safeArea 아님 )
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        if let req = initialRequest { webView.load(req) }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        webView.scrollView.contentInset = .zero
        webView.scrollView.scrollIndicatorInsets = .zero
        additionalSafeAreaInsets.bottom = 0
    }

    deinit {
        if Self.current === self { Self.current = nil }
    }

    @objc private func closeTapped() {
        dismiss(animated: true) { [weak self] in
            if PopupWebViewController.current === self { PopupWebViewController.current = nil }
        }
    }

    // window.open 대응: 동일 컨트롤러 안에서 새 뷰 생성
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        let child = WKWebView(frame: .zero, configuration: configuration)
        child.translatesAutoresizingMaskIntoConstraints = false
        child.navigationDelegate = self
        child.uiDelegate = self
        child.scrollView.contentInsetAdjustmentBehavior = .never
        child.scrollView.contentInset = .zero
        child.scrollView.scrollIndicatorInsets = .zero
        view.addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            child.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        return child
    }
}

