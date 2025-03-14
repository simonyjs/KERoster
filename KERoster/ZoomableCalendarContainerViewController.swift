//
//  ZoomableCalendarContainerViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/03/15.
//

import UIKit

class ZoomableCalendarContainerViewController: UIViewController {

    // 스토리보드나 다른 곳에서 데이터를 전달받기 위한 프로퍼티 추가
    var schedules: [String: [[String: String]]] = [:]
    var ownerInfo: String = ""
    var totalHours: String = ""

    // 줌 기능을 제공하는 스크롤 뷰
    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.minimumZoomScale = 0.5
        sv.maximumZoomScale = 3.0
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    // 기존 MonthlyCalendarViewController 인스턴스 생성
    private let calendarVC = MonthlyCalendarViewController()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        // 스크롤뷰 설정
        scrollView.delegate = self
        view.addSubview(scrollView)

        // calendarVC를 자식 뷰 컨트롤러로 추가
        addChild(calendarVC)
        
        // 컨테이너의 데이터를 자식 컨트롤러에 전달
        calendarVC.schedules = self.schedules
        calendarVC.ownerInfo = self.ownerInfo
        calendarVC.totalHours = self.totalHours

        calendarVC.view.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(calendarVC.view)
        calendarVC.didMove(toParent: self)

        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // 스크롤뷰 제약 조건
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // calendarVC.view 제약 조건
            calendarVC.view.topAnchor.constraint(equalTo: scrollView.topAnchor),
            calendarVC.view.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            calendarVC.view.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            calendarVC.view.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),

            // 캘린더 뷰의 너비와 높이를 스크롤뷰와 동일하게 설정하여 확대 축소 시 자연스럽게 동작하도록 함
            calendarVC.view.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            calendarVC.view.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
    }
}

// MARK: - UIScrollViewDelegate 구현 (핀치 줌 대상 지정)
extension ZoomableCalendarContainerViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return calendarVC.view // 캘린더 전체를 확대/축소 대상으로 지정
    }
}
