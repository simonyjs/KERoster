//
//  ExportStartDatePickerViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 12/15/25.
//

import UIKit

final class ExportStartDatePickerViewController: UIViewController {

    var initialDate: Date = Date()
    var onExport: ((Date) -> Void)?

    private let picker = UIDatePicker()
    private let todayButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        // iPad에서 팝업/시트가 과하게 커지는 문제 방지
        if traitCollection.userInterfaceIdiom == .pad {
            preferredContentSize = CGSize(width: 360, height: 360) // 필요하면 조절
        }

        // Header
        let titleLabel = UILabel()
        titleLabel.text = "Export Start Date"
        titleLabel.font = .boldSystemFont(ofSize: 17)

        todayButton.setTitle("TODAY", for: .normal)
        todayButton.titleLabel?.font = .boldSystemFont(ofSize: 14)
        todayButton.addTarget(self, action: #selector(tapToday), for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [titleLabel, UIView(), todayButton])
        header.axis = .horizontal
        header.alignment = .center

        // Picker
        picker.datePickerMode = .date
        picker.locale = Locale(identifier: "en_US_POSIX")
        picker.timeZone = TimeZone(identifier: "Asia/Seoul")
        picker.date = initialDate

        if #available(iOS 14.0, *) {
            // iPhone: wheels OK
            // iPad: compact가 더 공간 절약 (원하면 아래 2줄 주석 변경)
            if traitCollection.userInterfaceIdiom == .pad {
                picker.preferredDatePickerStyle = .wheels
                // picker.preferredDatePickerStyle = .compact
            } else {
                picker.preferredDatePickerStyle = .wheels
            }
        }

        // Buttons
        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.addTarget(self, action: #selector(tapCancel), for: .touchUpInside)

        let export = UIButton(type: .system)
        export.setTitle("Export", for: .normal)
        export.titleLabel?.font = .boldSystemFont(ofSize: 17)
        export.addTarget(self, action: #selector(tapExport), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [cancel, export])
        buttons.axis = .horizontal
        buttons.distribution = .fillEqually
        buttons.spacing = 12

        // Layout
        let root = UIStackView(arrangedSubviews: [header, picker, buttons])
        root.axis = .vertical
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            // bottom을 "equal"로 고정하면 iPad에서 늘어나며 공백이 생김 → <= 로 변경
            root.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            // wheels 기준 높이. compact로 바꾸면 220 대신 더 줄여도 됨
            picker.heightAnchor.constraint(equalToConstant: 220)
        ])

        // 남는 공간이 있으면 root를 가운데로(낮은 우선순위로)
        let centerY = root.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        centerY.priority = .defaultLow
        centerY.isActive = true
    }

    @objc private func tapToday() {
        picker.setDate(Date(), animated: true)
    }

    @objc private func tapCancel() {
        dismiss(animated: true)
    }

    @objc private func tapExport() {
        let picked = picker.date
        dismiss(animated: true) { [weak self] in
            self?.onExport?(picked)
        }
    }
}
