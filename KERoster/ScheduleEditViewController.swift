//
//  ScheduleEditViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/02/02.
//

import UIKit

// 델리게이트 프로토콜 (삭제 메서드 포함)
protocol ScheduleEditDelegate: AnyObject {
    func scheduleEditViewController(_ controller: ScheduleEditViewController, didSaveSchedule schedule: [String: String], at index: Int)
    func scheduleEditViewController(_ controller: ScheduleEditViewController, didDeleteScheduleAt index: Int)
}

class ScheduleEditViewController: UIViewController, UITextFieldDelegate {
    
    weak var delegate: ScheduleEditDelegate?
    var schedule: [String: String] = [:]
    var scheduleIndex: Int = 0
    
    // MARK: - WorkType 선택 컨트롤 (FLY, TVL 중 선택)
    let workTypeSegmentedControl = UISegmentedControl(items: ["FLY", "TVL"])
    
    // MARK: - FLY / TVL 전용 텍스트 필드들
    let depDateTextField = UITextField()      // 출발 날짜
    let arrDateTextField = UITextField()      // 도착 날짜
    let itemTextField = UITextField()         // C/S 항목
    let depApTextField = UITextField()        // DEP (출발 공항)
    let depStnTimeTextField = UITextField()   // STD (출발 시간) → 시간 피커 적용
    let arrApTextField = UITextField()        // DEST (도착 공항)
    let arrStnTimeTextField = UITextField()   // STA (도착 시간) → 시간 피커 적용
    let flyingHoursTextField = UITextField()  // Flying Hours
    let dutyHoursTextField = UITextField()    // Duty Hours
    
    // MARK: - 그 외 항목 (비 FLY/TVL일 경우 표시할 UI)
    let dateTextField = UITextField()         // DATE
    let activityTextField = UITextField()       // ACTIVITY
    let dutyReportTextField = UITextField()     // DUTY START
    let dutyDebriefTextField = UITextField()      // DUTY END
    
    // 메인 스택뷰 (모든 UI 요소를 담음)
    let mainStackView = UIStackView()
    
    // 현재 편집 중인 텍스트필드를 추적 (날짜/시간 선택 시 사용)
    var activeTextField: UITextField?
    
    // 날짜 포맷터 (날짜 선택 시 사용)
    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MMM-yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    // 시간 포맷터 (시간 선택 시 사용)
    let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm" // 24시간 형식 (원한다면 "hh:mm a"로 12시간 형식 가능)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        self.title = "Edit Schedule"
        // 다크모드에서도 라이트모드 강제 (글자가 잘 보이도록)
        overrideUserInterfaceStyle = .light
        
        // 내비게이션 바에 저장 버튼 추가
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save",
                                                            style: .done,
                                                            target: self,
                                                            action: #selector(saveTapped))
        
        setupUI()
    }
    
    func setupUI() {
        // 메인 스택뷰 설정 (상하좌우 여백 포함)
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
        
        // schedule["WorkType"]에 따라 UI 구성
        // 만약 WorkType이 "FLY" 또는 "TVL"이면 segmented control을 추가하고 FLY/TVL 전용 UI를 구성
        // 그 외이면 segmented control은 표시하지 않고, DATE, ACTIVITY, DUTY START, DUTY END만 표시
        if let workType = schedule["WorkType"], (workType == "FLY" || workType == "TVL") {
            // WorkType 선택 컨트롤 추가
            workTypeSegmentedControl.selectedSegmentIndex = (workType == "TVL") ? 1 : 0
            workTypeSegmentedControl.addTarget(self, action: #selector(workTypeChanged(_:)), for: .valueChanged)
            mainStackView.addArrangedSubview(workTypeSegmentedControl)
            setupFlyTVLUI()
        } else {
            // WorkType이 FLY/TVL이 아니라면 segmented control은 숨기고, 다른 항목만 표시
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
    
    // FLY/TVL 전용 UI 구성 (날짜 및 시간 선택은 DatePicker/TimePicker 사용)
    func setupFlyTVLUI() {
        // 출발 날짜
        configure(textField: depDateTextField, placeholder: "dd-MMM-yyyy", text: schedule["DepDate"])
        addDatePicker(to: depDateTextField)
        // 도착 날짜
        configure(textField: arrDateTextField, placeholder: "dd-MMM-yyyy", text: schedule["ArrDate"])
        addDatePicker(to: arrDateTextField)
        
        // C/S 항목 및 공항 정보는 일반 텍스트필드
        configure(textField: itemTextField, placeholder: "C/S", text: schedule["Item"])
        configure(textField: depApTextField, placeholder: "DEP", text: schedule["DepAp"])
        
        // STD (출발 시간): 시간 입력용 TimePicker 부착
        configure(textField: depStnTimeTextField, placeholder: "STD", text: schedule["DepStnTime"])
        addTimePicker(to: depStnTimeTextField)
        
        // DEST (도착 공항) 및 STA (도착 시간)
        configure(textField: arrApTextField, placeholder: "DEST", text: schedule["ArrAp"])
        configure(textField: arrStnTimeTextField, placeholder: "STA", text: schedule["ArrStnTime"])
        addTimePicker(to: arrStnTimeTextField)
        
        // Flying Hours, Duty Hours
        configure(textField: flyingHoursTextField, placeholder: "Flying Hours", text: schedule["FlyingHours"])
        configure(textField: dutyHoursTextField, placeholder: "Duty Hours", text: schedule["DutyHours"])
        
        // 각 필드를 왼쪽 설명(label)과 함께 배치
        let depDateStack = createLabeledField(labelText: "DEP DATE", textField: depDateTextField)
        let arrDateStack = createLabeledField(labelText: "ARR DATE", textField: arrDateTextField)
        let itemStack = createLabeledField(labelText: "C/S", textField: itemTextField)
        let depApStack = createLabeledField(labelText: "DEP", textField: depApTextField)
        let depTimeStack = createLabeledField(labelText: "STD", textField: depStnTimeTextField)
        let arrApStack = createLabeledField(labelText: "DEST", textField: arrApTextField)
        let arrTimeStack = createLabeledField(labelText: "STA", textField: arrStnTimeTextField)
        let flyingHoursStack = createLabeledField(labelText: "Flying Hrs", textField: flyingHoursTextField)
        let dutyHoursStack = createLabeledField(labelText: "Duty Hrs", textField: dutyHoursTextField)
        
        mainStackView.addArrangedSubview(depDateStack)
        mainStackView.addArrangedSubview(arrDateStack)
        mainStackView.addArrangedSubview(itemStack)
        mainStackView.addArrangedSubview(depApStack)
        mainStackView.addArrangedSubview(depTimeStack)
        mainStackView.addArrangedSubview(arrApStack)
        mainStackView.addArrangedSubview(arrTimeStack)
        mainStackView.addArrangedSubview(flyingHoursStack)
        mainStackView.addArrangedSubview(dutyHoursStack)
    }
    
    // 비 FLY/TVL 항목 UI 구성: 오직 DATE, ACTIVITY, DUTY START, DUTY END만 표시
    func setupOtherUI() {
        configure(textField: dateTextField, placeholder: "dd-MMM-yyyy", text: schedule["DepDate"])
        addDatePicker(to: dateTextField)
        
        configure(textField: activityTextField, placeholder: "ACTIVITY", text: schedule["Activity"])
        configure(textField: dutyReportTextField, placeholder: "DUTY START", text: schedule["DutyReport"])
        configure(textField: dutyDebriefTextField, placeholder: "DUTY END", text: schedule["DutyDebrief"])
        
        let dateStack = createLabeledField(labelText: "DATE", textField: dateTextField)
        let activityStack = createLabeledField(labelText: "ACTIVITY", textField: activityTextField)
        let reportStack = createLabeledField(labelText: "DUTY START", textField: dutyReportTextField)
        let debriefStack = createLabeledField(labelText: "DUTY END", textField: dutyDebriefTextField)
        
        mainStackView.addArrangedSubview(dateStack)
        mainStackView.addArrangedSubview(activityStack)
        mainStackView.addArrangedSubview(reportStack)
        mainStackView.addArrangedSubview(debriefStack)
    }
    
    // 헬퍼 메서드: 텍스트필드 기본 설정 (텍스트 색상 및 delegate 지정)
    func configure(textField: UITextField, placeholder: String, text: String?) {
        textField.placeholder = placeholder
        textField.borderStyle = .roundedRect
        textField.text = text
        textField.textColor = .black
        // 날짜 입력 필드라면 delegate 지정 (시간 필드는 별도 처리)
        if placeholder == "dd-MMM-yyyy" {
            textField.delegate = self
        }
    }
    
    // 헬퍼 메서드: 왼쪽 설명(label)과 텍스트필드를 포함하는 수평 스택뷰 생성
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
    
    // 날짜 입력용 DatePicker 부착
    func addDatePicker(to textField: UITextField) {
        let datePicker = UIDatePicker()
        datePicker.datePickerMode = .date
        if #available(iOS 13.4, *) {
            datePicker.preferredDatePickerStyle = .wheels
        }
        datePicker.addTarget(self, action: #selector(dateChanged(_:)), for: .valueChanged)
        textField.inputView = datePicker
        
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(donePressed))
        toolbar.setItems([doneButton], animated: false)
        textField.inputAccessoryView = toolbar
    }
    
    // 시간 입력용 TimePicker 부착
    func addTimePicker(to textField: UITextField) {
        let timePicker = UIDatePicker()
        timePicker.datePickerMode = .time
        if #available(iOS 13.4, *) {
            timePicker.preferredDatePickerStyle = .wheels
        }
        timePicker.addTarget(self, action: #selector(timeChanged(_:)), for: .valueChanged)
        textField.inputView = timePicker
        
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(donePressed))
        toolbar.setItems([doneButton], animated: false)
        textField.inputAccessoryView = toolbar
    }
    
    // MARK: - UITextFieldDelegate
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        activeTextField = textField
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        activeTextField = nil
    }
    
    // DatePicker 값 변경 시 호출 (날짜 포맷터 적용)
    @objc func dateChanged(_ sender: UIDatePicker) {
        activeTextField?.text = dateFormatter.string(from: sender.date)
    }
    
    // TimePicker 값 변경 시 호출 (시간 포맷터 적용)
    @objc func timeChanged(_ sender: UIDatePicker) {
        activeTextField?.text = timeFormatter.string(from: sender.date)
    }
    
    // 도구모음의 완료 버튼 클릭 시 키보드(피커) 내림
    @objc func donePressed() {
        activeTextField?.resignFirstResponder()
    }
    
    // WorkType 선택 변경 시 (세그먼트 컨트롤)
    @objc func workTypeChanged(_ sender: UISegmentedControl) {
        let selected = sender.titleForSegment(at: sender.selectedSegmentIndex) ?? "FLY"
        schedule["WorkType"] = selected
        // 필요한 경우 UI를 재구성할 수 있음 (여기서는 FLY/TVL UI가 동일하다고 가정)
    }
    
    @objc func saveTapped() {
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
        present(alert, animated: true, completion: nil)
    }
}
