//
//  ScheduleEditViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/02/02.
//

import UIKit

// 만약 ScheduleEditDelegate가 이미 다른 파일에 선언되어 있다면 아래 코드를 제거하세요.
//protocol ScheduleEditDelegate: AnyObject {
//    func scheduleEditViewController(_ controller: ScheduleEditViewController, didSaveSchedule schedule: [String: String], at index: Int)
//    func scheduleEditViewController(_ controller: ScheduleEditViewController, didDeleteScheduleAt index: Int)
//}

class ScheduleEditViewController: UIViewController, UITextFieldDelegate {
    
    weak var delegate: ScheduleEditDelegate?
    var schedule: [String: String] = [:]
    var scheduleIndex: Int = 0
    
    // MARK: - FLY/TVL 전용 UI 요소
    let workTypeSegmentedControl = UISegmentedControl(items: ["FLY", "TVL"])
    let depDateTextField = UITextField()      // 출발 날짜
    let arrDateTextField = UITextField()      // 도착 날짜
    let itemTextField = UITextField()         // C/S 항목
    let depApTextField = UITextField()        // DEP (출발 공항)
    let depStnTimeTextField = UITextField()   // STD (출발 시간) → 원래 시간 피커 사용, 지금은 주석 처리됨
    let arrApTextField = UITextField()        // DEST (도착 공항)
    let arrStnTimeTextField = UITextField()   // STA (도착 시간) → 원래 시간 피커 사용, 지금은 주석 처리됨
    let flyingHoursTextField = UITextField()  // Flying Hours
    let dutyHoursTextField = UITextField()    // Duty Hours
    
    // MARK: - 그 외 UI 요소 (비 FLY/TVL일 경우)
    let dateTextField = UITextField()         // DATE
    let activityTextField = UITextField()       // ACTIVITY
    let dutyReportTextField = UITextField()     // DUTY START
    let dutyDebriefTextField = UITextField()    // DUTY END
    
    // 메인 스택뷰 (모든 UI 요소를 담음)
    let mainStackView = UIStackView()
    
    // MARK: - Date & Time Formatters
    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MMM-yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm" // 24시간 형식 (원한다면 "hh:mm a"로 변경 가능)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    // MARK: - View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        self.title = "Edit Schedule"
        // 다크모드에서도 항상 라이트모드 적용 (가독성 확보)
        overrideUserInterfaceStyle = .light
        
        // 내비게이션 바에 저장 버튼 추가
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save",
                                                            style: .done,
                                                            target: self,
                                                            action: #selector(saveTapped))
        setupUI()
    }
    
    // MARK: - UI 구성
    func setupUI() {
        // 메인 스택뷰 설정 및 제약조건 추가
        mainStackView.axis = .vertical
        mainStackView.spacing = 16
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStackView)
        
        NSLayoutConstraint.activate([
            mainStackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            mainStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            mainStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            mainStackView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -16)
        ])
        
        // WorkType에 따라 UI 구성 분기
        if let workType = schedule["WorkType"], (workType == "FLY" || workType == "TVL") {
            // FLY/TVL인 경우 segmented control과 관련 UI 구성
            workTypeSegmentedControl.selectedSegmentIndex = (workType == "TVL") ? 1 : 0
            workTypeSegmentedControl.addTarget(self, action: #selector(workTypeChanged(_:)), for: .valueChanged)
            mainStackView.addArrangedSubview(workTypeSegmentedControl)
            setupFlyTVLUI()
        } else {
            // FLY/TVL이 아닌 경우
            setupOtherUI()
        }
        
        // 삭제 버튼 추가 (스택뷰의 마지막에 배치)
        let deleteButton = UIButton(type: .system)
        deleteButton.setTitle("Delete Schedule", for: .normal)
        deleteButton.setTitleColor(.white, for: .normal)
        deleteButton.backgroundColor = .red
        deleteButton.layer.cornerRadius = 5
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        deleteButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        mainStackView.addArrangedSubview(deleteButton)
    }
    
    // MARK: - WorkType 변경 액션
    @objc func workTypeChanged(_ sender: UISegmentedControl) {
        let selectedWorkType = sender.titleForSegment(at: sender.selectedSegmentIndex) ?? "FLY"
        schedule["WorkType"] = selectedWorkType
        
        // 기존 UI 제거 후 다시 구성
        mainStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        mainStackView.addArrangedSubview(workTypeSegmentedControl)
        
        if selectedWorkType == "FLY" || selectedWorkType == "TVL" {
            setupFlyTVLUI()
        } else {
            setupOtherUI()
        }
    }
    
    /// FLY/TVL 전용 UI 구성 – 원래는 날짜와 시간 입력을 위해 DatePicker/TimePicker를 사용하지만,
    /// 지금은 주석 처리하여 사용자가 직접 입력할 수 있도록 함.
    func setupFlyTVLUI() {
        // 출발 날짜
        configure(textField: depDateTextField, placeholder: "dd-MMM-yyyy", text: schedule["DepDate"])
        // addDatePicker(to: depDateTextField) // Picker 사용 대신 수동 입력
        // 도착 날짜
        configure(textField: arrDateTextField, placeholder: "dd-MMM-yyyy", text: schedule["ArrDate"])
        // addDatePicker(to: arrDateTextField) // Picker 사용 대신 수동 입력
        
        // C/S, DEP 정보
        configure(textField: itemTextField, placeholder: "C/S", text: schedule["Item"])
        configure(textField: depApTextField, placeholder: "DEP", text: schedule["DepAp"])
        
        // STD (출발 시간)
        configure(textField: depStnTimeTextField, placeholder: "STD", text: schedule["DepStnTime"])
        // addTimePicker(to: depStnTimeTextField) // Picker 사용 대신 수동 입력
        
        // DEST (도착 공항) 및 STA (도착 시간)
        configure(textField: arrApTextField, placeholder: "DEST", text: schedule["ArrAp"])
        configure(textField: arrStnTimeTextField, placeholder: "STA", text: schedule["ArrStnTime"])
        // addTimePicker(to: arrStnTimeTextField) // Picker 사용 대신 수동 입력
        
        // Flying Hours, Duty Hours
        configure(textField: flyingHoursTextField, placeholder: "Flying Hours", text: schedule["FlyingHours"])
        configure(textField: dutyHoursTextField, placeholder: "Duty Hours", text: schedule["DutyHours"])
        
        // 각 항목을 왼쪽 설명(label)과 함께 수평 스택뷰로 배치 후, 메인 스택뷰에 추가
        let depDateStack = createLabeledField(labelText: "DEP DATE", textField: depDateTextField)
        let arrDateStack = createLabeledField(labelText: "ARR DATE", textField: arrDateTextField)
        let itemStack = createLabeledField(labelText: "C/S", textField: itemTextField)
        let depApStack = createLabeledField(labelText: "DEP", textField: depApTextField)
        let depTimeStack = createLabeledField(labelText: "STD", textField: depStnTimeTextField)
        let arrApStack = createLabeledField(labelText: "DEST", textField: arrApTextField)
        let arrTimeStack = createLabeledField(labelText: "STA", textField: arrStnTimeTextField)
        let flyingHoursStack = createLabeledField(labelText: "Flying Hrs", textField: flyingHoursTextField)
        let dutyHoursStack = createLabeledField(labelText: "Duty Hrs", textField: dutyHoursTextField)
        
        [depDateStack, arrDateStack, itemStack, depApStack, depTimeStack, arrApStack, arrTimeStack, flyingHoursStack, dutyHoursStack].forEach {
            mainStackView.addArrangedSubview($0)
        }
    }
    
    /// FLY/TVL가 아닌 경우 UI 구성 – DATE, ACTIVITY, DUTY START, DUTY END만 표시
    func setupOtherUI() {
        configure(textField: dateTextField, placeholder: "dd-MMM-yyyy", text: schedule["DepDate"])
        // addDatePicker(to: dateTextField) // Picker 사용 대신 수동 입력
        configure(textField: activityTextField, placeholder: "ACTIVITY", text: schedule["Activity"])
        configure(textField: dutyReportTextField, placeholder: "DUTY START", text: schedule["DutyReport"])
        configure(textField: dutyDebriefTextField, placeholder: "DUTY END", text: schedule["DutyDebrief"])
        
        let dateStack = createLabeledField(labelText: "DATE", textField: dateTextField)
        let activityStack = createLabeledField(labelText: "ACTIVITY", textField: activityTextField)
        let reportStack = createLabeledField(labelText: "DUTY START", textField: dutyReportTextField)
        let debriefStack = createLabeledField(labelText: "DUTY END", textField: dutyDebriefTextField)
        
        [dateStack, activityStack, reportStack, debriefStack].forEach {
            mainStackView.addArrangedSubview($0)
        }
    }
    
    // MARK: - Helper Methods
    
    /// 텍스트필드의 기본 설정 (placeholder, border, 텍스트 색상 등)
    func configure(textField: UITextField, placeholder: String, text: String?) {
        textField.placeholder = placeholder
        textField.borderStyle = .roundedRect
        textField.text = text
        textField.textColor = .black
        textField.delegate = self
    }
    
    /// 왼쪽에 label과 텍스트필드를 포함하는 수평 스택뷰 생성
    func createLabeledField(labelText: String, textField: UITextField) -> UIStackView {
        let label = UILabel()
        label.text = labelText
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .black
        label.textAlignment = .left
        label.widthAnchor.constraint(equalToConstant: 100).isActive = true
        
        let hStack = UIStackView(arrangedSubviews: [label, textField])
        hStack.axis = .horizontal
        hStack.spacing = 8
        return hStack
    }
    
    // MARK: - UITextFieldDelegate
    func textFieldDidBeginEditing(_ textField: UITextField) {
        // 현재 편집 중인 텍스트필드를 추적 (필요에 따라 추가 구현)
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        // 편집 종료 시 추적 제거 (필요에 따라 추가 구현)
    }
    
    /// 입력 형식 검증: 날짜는 dd-MMM-yyyy, 시간은 HH:mm 형식 체크
    func validateInputFormat() -> Bool {
        let dateFields = [depDateTextField, arrDateTextField, dateTextField]
        let timeFields = [depStnTimeTextField, arrStnTimeTextField, dutyReportTextField, dutyDebriefTextField]
        
        for textField in dateFields {
            if let text = textField.text, !text.isEmpty {
                if dateFormatter.date(from: text) == nil {
                    showAlert(title: "Invalid Date", message: "Please enter a valid date in format: dd-MMM-yyyy")
                    return false
                }
            }
        }
        
        for textField in timeFields {
            if let text = textField.text, !text.isEmpty {
                if timeFormatter.date(from: text) == nil {
                    showAlert(title: "Invalid Time", message: "Please enter a valid time in format: HH:mm")
                    return false
                }
            }
        }
        
        return true
    }
    
    @objc func saveTapped() {
        guard validateInputFormat() else { return }
        
        var updatedSchedule = schedule
        let workType = schedule["WorkType"] ?? "FLY"
        if workType == "FLY" || workType == "TVL" {
            updatedSchedule["DepDate"] = depDateTextField.text
            updatedSchedule["ArrDate"] = arrDateTextField.text
            updatedSchedule["Item"] = itemTextField.text
            updatedSchedule["DepAp"] = depApTextField.text
            updatedSchedule["DepStnTime"] = depStnTimeTextField.text
            updatedSchedule["ArrAp"] = arrApTextField.text
            updatedSchedule["ArrStnTime"] = arrStnTimeTextField.text
            updatedSchedule["FlyingHours"] = flyingHoursTextField.text
            updatedSchedule["DutyHours"] = dutyHoursTextField.text
        } else {
            updatedSchedule["DepDate"] = dateTextField.text
            updatedSchedule["Activity"] = activityTextField.text
            updatedSchedule["DutyReport"] = dutyReportTextField.text
            updatedSchedule["DutyDebrief"] = dutyDebriefTextField.text
        }
        
        delegate?.scheduleEditViewController(self, didSaveSchedule: updatedSchedule, at: scheduleIndex)
        navigationController?.popViewController(animated: true)
    }
    
    @objc func deleteTapped() {
        let alert = UIAlertController(title: "Delete Schedule",
                                      message: "Are you sure you want to delete this schedule?",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { _ in
            self.delegate?.scheduleEditViewController(self, didDeleteScheduleAt: self.scheduleIndex)
            self.navigationController?.popViewController(animated: true)
        }))
        present(alert, animated: true)
    }
    
    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true)
    }
}
