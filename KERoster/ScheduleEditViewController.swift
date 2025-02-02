//
//  ScheduleEditViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/02/02.
//

import UIKit

// 델리게이트 프로토콜 정의
protocol ScheduleEditDelegate: AnyObject {
    func scheduleEditViewController(_ controller: ScheduleEditViewController, didSaveSchedule schedule: [String: String], at index: Int)
}

class ScheduleEditViewController: UIViewController {
    
    weak var delegate: ScheduleEditDelegate?
    var schedule: [String: String] = [:]
    var scheduleIndex: Int = 0
    
    // 수정할 항목을 위한 텍스트 필드들
    let depApTextField = UITextField()
    let arrApTextField = UITextField()
    let depTimeTextField = UITextField()
    let arrTimeTextField = UITextField()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        self.title = "Edit Schedule"
        
        setupTextFields()
        
        // 내비게이션 바에 저장 버튼 추가
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save",
                                                            style: .done,
                                                            target: self,
                                                            action: #selector(saveTapped))
    }
    
    func setupTextFields() {
        // 텍스트 필드 설정
        depApTextField.placeholder = "Dep Ap"
        depApTextField.borderStyle = .roundedRect
        depApTextField.text = schedule["DepAp"]
        
        arrApTextField.placeholder = "Arr Ap"
        arrApTextField.borderStyle = .roundedRect
        arrApTextField.text = schedule["ArrAp"]
        
        depTimeTextField.placeholder = "Dep Time"
        depTimeTextField.borderStyle = .roundedRect
        depTimeTextField.text = schedule["DepStnTime"]
        
        arrTimeTextField.placeholder = "Arr Time"
        arrTimeTextField.borderStyle = .roundedRect
        arrTimeTextField.text = schedule["ArrStnTime"]
        
        // 텍스트 필드들을 수직 스택 뷰에 배치
        let stackView = UIStackView(arrangedSubviews: [depApTextField, arrApTextField, depTimeTextField, arrTimeTextField])
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }
    
    @objc func saveTapped() {
        // 텍스트 필드의 값을 수정된 스케줄 딕셔너리에 업데이트
        var updatedSchedule = schedule
        updatedSchedule["DepAp"] = depApTextField.text
        updatedSchedule["ArrAp"] = arrApTextField.text
        updatedSchedule["DepStnTime"] = depTimeTextField.text
        updatedSchedule["ArrStnTime"] = arrTimeTextField.text
        
        // 델리게이트를 통해 수정된 스케줄을 전달
        delegate?.scheduleEditViewController(self, didSaveSchedule: updatedSchedule, at: scheduleIndex)
        navigationController?.popViewController(animated: true)
    }
}
