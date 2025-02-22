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
    let depStnTimeTextField = UITextField()   // STD (출발 시간)
    let arrApTextField = UITextField()        // DEST (도착 공항)
    let arrStnTimeTextField = UITextField()   // STA (도착 시간)
    let flyingHoursTextField = UITextField()  // Flying Hours
    let dutyHoursTextField = UITextField()    // Duty Hours
    
    // MARK: - OTHER 타입 UI 요소 (수동 입력)
    // OTHER 타입에서는 시작 날짜, 종료 날짜, ACTIVITY, DUTY START, DUTY END, 그리고 추가 노트를 입력받습니다.
    let dateTextField = UITextField()         // 시작 날짜
    let endDateTextField = UITextField()        // 종료 날짜
    let activityTextField = UITextField()       // ACTIVITY
    let dutyReportTextField = UITextField()     // DUTY 시작 시간
    let dutyDebriefTextField = UITextField()    // DUTY 종료 시간
    let noteTextField = UITextField()           // 추가 노트 입력
    
    // 메인 스택뷰 (모든 UI 요소를 담음)
    let mainStackView = UIStackView()
    
    // MARK: - Date & Time Formatters
    // 저장 시 사용 형식: "dd-MMM-yyyy"
    let storageDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MMM-yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    // 사용자 입력/표시 시 사용 형식: "yyyy-MM-dd"
    let inputDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm" // 24시간 형식
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    // MARK: - View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        self.title = "Edit Schedule"
        // 항상 라이트 모드 사용
        overrideUserInterfaceStyle = .light
        
        // 내비게이션 바에 저장 버튼 추가
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save",
                                                            style: .done,
                                                            target: self,
                                                            action: #selector(saveTapped))
        setupUI()
    }
    
    // MARK: - UI 구성 및 Auto Layout
    func setupUI() {
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
            workTypeSegmentedControl.selectedSegmentIndex = (workType == "TVL") ? 1 : 0
            workTypeSegmentedControl.addTarget(self, action: #selector(workTypeChanged(_:)), for: .valueChanged)
            mainStackView.addArrangedSubview(workTypeSegmentedControl)
            setupFlyTVLUI()
        } else {
            setupOtherUI()
        }
        
        // 삭제 버튼 추가 (맨 마지막)
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
        
        // 삭제 버튼 추가 (맨 마지막)
        let deleteButton = UIButton(type: .system)
        deleteButton.setTitle("Delete Schedule", for: .normal)
        deleteButton.setTitleColor(.white, for: .normal)
        deleteButton.backgroundColor = .red
        deleteButton.layer.cornerRadius = 5
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        deleteButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        mainStackView.addArrangedSubview(deleteButton)
    }
    
    /// FLY/TVL 전용 UI 구성 – 입력 형식은 "yyyy-MM-dd" (저장 시 "dd-MMM-yyyy"로 변환)
    func setupFlyTVLUI() {
        configure(textField: depDateTextField, placeholder: "yyyy-MM-dd", text: convertStoredDateToInput(schedule["DepDate"]))
        configure(textField: arrDateTextField, placeholder: "yyyy-MM-dd", text: convertStoredDateToInput(schedule["ArrDate"]))
        configure(textField: itemTextField, placeholder: "Item (C/S)", text: schedule["Item"])
        configure(textField: depApTextField, placeholder: "DEP", text: schedule["DepAp"])
        configure(textField: depStnTimeTextField, placeholder: "STD", text: schedule["DepStnTime"])
        configure(textField: arrApTextField, placeholder: "DEST", text: schedule["ArrAp"])
        configure(textField: arrStnTimeTextField, placeholder: "STA", text: schedule["ArrStnTime"])
        configure(textField: flyingHoursTextField, placeholder: "Flying Hours", text: schedule["FlyingHours"])
        configure(textField: dutyHoursTextField, placeholder: "Duty Hours", text: schedule["DutyHours"])
        
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
    
    /// OTHER 타입 UI 구성 – 입력 형식은 "yyyy-MM-dd"
    /// 시작 날짜, 종료 날짜, ACTIVITY, DUTY START, DUTY END, 그리고 추가 노트를 입력받음
    func setupOtherUI() {
        configure(textField: dateTextField, placeholder: "yyyy-MM-dd", text: convertStoredDateToInput(schedule["DepDate"]))
        configure(textField: endDateTextField, placeholder: "yyyy-MM-dd", text: convertStoredDateToInput(schedule["DutyDebriefDate"]))
        configure(textField: activityTextField, placeholder: "ACTIVITY", text: schedule["Activity"])
        configure(textField: dutyReportTextField, placeholder: "DUTY START", text: schedule["DutyReport"])
        configure(textField: dutyDebriefTextField, placeholder: "DUTY END", text: schedule["DutyDebrief"])
        configure(textField: noteTextField, placeholder: "Enter additional note (optional)", text: schedule["Note"])
        
        let dateStack = createLabeledField(labelText: "START DATE", textField: dateTextField)
        let endDateStack = createLabeledField(labelText: "END DATE", textField: endDateTextField)
        let activityStack = createLabeledField(labelText: "ACTIVITY", textField: activityTextField)
        let reportStack = createLabeledField(labelText: "DUTY START", textField: dutyReportTextField)
        let debriefStack = createLabeledField(labelText: "DUTY END", textField: dutyDebriefTextField)
        let noteStack = createLabeledField(labelText: "NOTE", textField: noteTextField)
        
        [dateStack, endDateStack, activityStack, reportStack, debriefStack, noteStack].forEach {
            mainStackView.addArrangedSubview($0)
        }
    }
    
    // MARK: - Helper: 저장된 날짜("dd-MMM-yyyy")를 "yyyy-MM-dd" 형식으로 변환
    func convertStoredDateToInput(_ storedDate: String?) -> String? {
        guard let stored = storedDate, let date = storageDateFormatter.date(from: stored) else { return storedDate }
        return inputDateFormatter.string(from: date)
    }
    
    // MARK: - Helper Methods (텍스트필드 설정 및 스택뷰 생성)
    func configure(textField: UITextField, placeholder: String, text: String?) {
        textField.placeholder = placeholder
        textField.borderStyle = .roundedRect
        textField.text = text
        textField.textColor = .black
        textField.delegate = self
    }
    
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
    
    // MARK: - Action Methods
    @objc func saveTapped() {
        let inputDF = DateFormatter()
        inputDF.dateFormat = "yyyy-MM-dd"
        inputDF.locale = Locale(identifier: "en_US_POSIX")
        
        let outputDF = DateFormatter()
        outputDF.dateFormat = "dd-MMM-yyyy"
        outputDF.locale = Locale(identifier: "en_US_POSIX")
        
        func isValidTime(_ time: String) -> Bool {
            let regex = "^([01]\\d|2[0-3]):([0-5]\\d)$"
            return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: time)
        }
        
        let currentWorkType = schedule["WorkType"] ?? ""
        var updatedSchedule = schedule
        
        if currentWorkType == "FLY" || currentWorkType == "TVL" {
            guard let depDateInput = depDateTextField.text,
                  let depDate = inputDF.date(from: depDateInput) else {
                showAlert(title: "Invalid Date", message: "Please enter a valid departure date in format yyyy-MM-dd.")
                return
            }
            guard let arrDateInput = arrDateTextField.text,
                  let arrDate = inputDF.date(from: arrDateInput) else {
                showAlert(title: "Invalid Date", message: "Please enter a valid arrival date in format yyyy-MM-dd.")
                return
            }
            updatedSchedule["DepDate"] = outputDF.string(from: depDate)
            updatedSchedule["ArrDate"] = outputDF.string(from: arrDate)
            updatedSchedule["Item"] = itemTextField.text
            updatedSchedule["DepAp"] = depApTextField.text
            updatedSchedule["DepStnTime"] = depStnTimeTextField.text
            updatedSchedule["ArrAp"] = arrApTextField.text
            updatedSchedule["ArrStnTime"] = arrStnTimeTextField.text
            updatedSchedule["FlyingHours"] = flyingHoursTextField.text
            updatedSchedule["DutyHours"] = dutyHoursTextField.text
        } else {
            guard let startDateInput = dateTextField.text,
                  let startDate = inputDF.date(from: startDateInput) else {
                showAlert(title: "Invalid Date", message: "Please enter a valid start date in format yyyy-MM-dd.")
                return
            }
            guard let endDateInput = endDateTextField.text,
                  let endDate = inputDF.date(from: endDateInput) else {
                showAlert(title: "Invalid Date", message: "Please enter a valid end date in format yyyy-MM-dd.")
                return
            }
            let dayDiff = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
            if dayDiff < 0 {
                showAlert(title: "Invalid Date", message: "End date cannot be before start date.")
                return
            }
            updatedSchedule["DepDate"] = outputDF.string(from: startDate)
            updatedSchedule["DutyDebriefDate"] = outputDF.string(from: endDate)
            
            if let activity = activityTextField.text, !activity.isEmpty {
                updatedSchedule["Activity"] = activity.uppercased()
            }
            guard let startTime = dutyReportTextField.text, isValidTime(startTime) else {
                showAlert(title: "Invalid Time", message: "Please enter a valid duty start time in format HH:mm.")
                return
            }
            updatedSchedule["DutyReport"] = startTime
            
            guard let endTime = dutyDebriefTextField.text, isValidTime(endTime) else {
                showAlert(title: "Invalid Time", message: "Please enter a valid duty end time in format HH:mm.")
                return
            }
            updatedSchedule["DutyDebrief"] = endTime
            
            // Note 저장
            updatedSchedule["Note"] = noteTextField.text ?? ""
        }
        
        if currentWorkType == "FLY" || currentWorkType == "TVL" {
            updatedSchedule["TimeZoneIATA"] = ""
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
            // 삭제 시 delegate를 호출하여 상위 컨트롤러에서 글로벌 스케줄 업데이트가 진행되도록 함
            self.delegate?.scheduleEditViewController(self, didDeleteScheduleAt: self.scheduleIndex)
            self.navigationController?.popViewController(animated: true)
        }))
        present(alert, animated: true, completion: nil)
    }
    
    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title,
                                      message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
}
