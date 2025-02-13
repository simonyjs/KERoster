//
//  ScheduleInputFormViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/02/12.
//

import UIKit

class ScheduleInputFormViewController: UIViewController, UITextFieldDelegate {
    
    // 달력에서 전달받은 선택 날짜 (Date 타입)
    var selectedDate: Date?
    
    // 스케줄 저장용 UserDefaults key
    let schedulesUserDefaultsKey = "schedules"
    
    // 스크롤뷰와 스택뷰 (입력폼들을 담기 위함)
    let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        // 폼 전체 배경색을 검은색으로 고정
        sv.backgroundColor = UIColor.black
        return sv
    }()
    
    let mainStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    // 근무타입 선택 (FLY, TVL, OTHER)
    let workTypeSegmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["FLY", "TVL", "OTHER"])
        control.selectedSegmentIndex = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        // 텍스트 색상은 흰색으로 고정
        control.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        return control
    }()
    
    // MARK: - FLY/TVL 타입 전용 입력 UI
    let depDatePicker: UIDatePicker = {
        let picker = UIDatePicker()
        if #available(iOS 14.0, *) { picker.preferredDatePickerStyle = .inline }
        picker.datePickerMode = .date
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.backgroundColor = UIColor.black
        // UIDatePicker 내부 텍스트 색상은 흰색 (비공식 API)
        picker.setValue(UIColor.white, forKey: "textColor")
        return picker
    }()
    
    let arrDatePicker: UIDatePicker = {
        let picker = UIDatePicker()
        if #available(iOS 14.0, *) { picker.preferredDatePickerStyle = .inline }
        picker.datePickerMode = .date
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.backgroundColor = UIColor.black
        picker.setValue(UIColor.white, forKey: "textColor")
        return picker
    }()
    
    let itemTextField = UITextField()
    let depApTextField = UITextField()
    let depStnTimeTextField = UITextField()
    let arrApTextField = UITextField()
    let arrStnTimeTextField = UITextField()
    let flyingHoursTextField = UITextField()
    let dutyHoursTextField = UITextField()
    
    // MARK: - OTHER 타입 전용 입력 UI
    let startDatePicker: UIDatePicker = {
        let picker = UIDatePicker()
        if #available(iOS 14.0, *) { picker.preferredDatePickerStyle = .inline }
        picker.datePickerMode = .date
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.backgroundColor = UIColor.black
        picker.setValue(UIColor.white, forKey: "textColor")
        return picker
    }()
    
    let endDatePicker: UIDatePicker = {
        let picker = UIDatePicker()
        if #available(iOS 14.0, *) { picker.preferredDatePickerStyle = .inline }
        picker.datePickerMode = .date
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.backgroundColor = UIColor.black
        picker.setValue(UIColor.white, forKey: "textColor")
        return picker
    }()
    
    let activityTextField = UITextField()
    let dutyReportTextField = UITextField()        // 근무 시작시간
    let dutyDebriefTextField = UITextField()         // 근무 종료시간

    override func viewDidLoad() {
        super.viewDidLoad()
        // 전체 배경 검은색
        view.backgroundColor = UIColor.black
        self.title = "스케줄 입력"
        
        setupScrollView()
        setupMainStackView()
        configureSegmentedControl()
        
        // 초기에는 FLY/TVL 입력폼 표시
        setupFlyTVLUI()
        addSaveButton()
        
        // 선택된 날짜가 있다면 기본값 설정
        if let preselectedDate = selectedDate {
            depDatePicker.date = preselectedDate
            arrDatePicker.date = preselectedDate
            startDatePicker.date = preselectedDate
            endDatePicker.date = preselectedDate
        }
        
        // 키보드 옵저버 등록
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillShow(notification:)),
                                               name: UIResponder.keyboardWillShowNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillHide(notification:)),
                                               name: UIResponder.keyboardWillHideNotification,
                                               object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - 스크롤뷰 및 스택뷰 설정
    func setupScrollView() {
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    func setupMainStackView() {
        scrollView.addSubview(mainStackView)
        NSLayoutConstraint.activate([
            mainStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            mainStackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            mainStackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            mainStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16)
        ])
    }
    
    // MARK: - 키보드 대응
    @objc func keyboardWillShow(notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        scrollView.contentInset.bottom = keyboardFrame.height
        scrollView.verticalScrollIndicatorInsets.bottom = keyboardFrame.height
    }
    
    @objc func keyboardWillHide(notification: Notification) {
        scrollView.contentInset.bottom = 0
        scrollView.verticalScrollIndicatorInsets.bottom = 0
    }
    
    // MARK: - UI 설정
    func configureSegmentedControl() {
        workTypeSegmentedControl.addTarget(self, action: #selector(workTypeChanged(_:)), for: .valueChanged)
        mainStackView.addArrangedSubview(workTypeSegmentedControl)
    }
    
    // 레이블과 텍스트필드 수평 스택뷰 생성 (배경 검정, 텍스트 흰색)
    func createLabeledField(labelText: String, textField: UITextField) -> UIStackView {
        let label = UILabel()
        label.text = labelText
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = UIColor.white
        label.widthAnchor.constraint(equalToConstant: 100).isActive = true
        
        textField.placeholder = labelText
        textField.borderStyle = .roundedRect
        textField.textColor = UIColor.white
        textField.backgroundColor = UIColor.darkGray
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.heightAnchor.constraint(equalToConstant: 30).isActive = true
        
        let hStack = UIStackView(arrangedSubviews: [label, textField])
        hStack.axis = .horizontal
        hStack.spacing = 8
        return hStack
    }
    
    // 레이블과 UIDatePicker로 구성된 수직 스택뷰 생성 (배경 검정, 텍스트 흰색)
    func createLabeledPicker(labelText: String, picker: UIDatePicker) -> UIStackView {
        let label = UILabel()
        label.text = labelText
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = UIColor.white
        
        let vStack = UIStackView(arrangedSubviews: [label, picker])
        vStack.axis = .vertical
        vStack.spacing = 4
        return vStack
    }
    
    /// FLY/TVL 입력폼 구성
    func setupFlyTVLUI() {
        // 기존 입력폼 제거 (세그먼트 컨트롤 제외)
        mainStackView.arrangedSubviews.forEach { view in
            if view !== workTypeSegmentedControl {
                view.removeFromSuperview()
            }
        }
        
        mainStackView.addArrangedSubview(createLabeledPicker(labelText: "STD Date", picker: depDatePicker))
        mainStackView.addArrangedSubview(createLabeledPicker(labelText: "STA Date", picker: arrDatePicker))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "C/S", textField: itemTextField))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "DEP", textField: depApTextField))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "STD", textField: depStnTimeTextField))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "ARR", textField: arrApTextField))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "STA", textField: arrStnTimeTextField))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "Flying Hours", textField: flyingHoursTextField))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "Duty Hours", textField: dutyHoursTextField))
    }
    
    /// OTHER 입력폼 구성
    func setupOtherUI() {
        mainStackView.arrangedSubviews.forEach { view in
            if view !== workTypeSegmentedControl {
                view.removeFromSuperview()
            }
        }
        
        mainStackView.addArrangedSubview(createLabeledPicker(labelText: "Start Date", picker: startDatePicker))
        mainStackView.addArrangedSubview(createLabeledPicker(labelText: "End Date", picker: endDatePicker))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "Activity", textField: activityTextField))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "Start Time", textField: dutyReportTextField))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "End Time", textField: dutyDebriefTextField))
    }
    
    func configure(textField: UITextField, placeholder: String) {
        textField.placeholder = placeholder
        textField.borderStyle = .roundedRect
        textField.textColor = UIColor.white
        textField.backgroundColor = UIColor.darkGray
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.heightAnchor.constraint(equalToConstant: 30).isActive = true
    }
    
    func addSaveButton() {
        let saveButton = UIButton(type: .system)
        saveButton.setTitle("Save Schedule", for: .normal)
        saveButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
        saveButton.backgroundColor = UIColor.systemBlue
        saveButton.tintColor = UIColor.white
        saveButton.layer.cornerRadius = 5
        saveButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        mainStackView.addArrangedSubview(saveButton)
    }
    
    // MARK: - Action Methods
    @objc func workTypeChanged(_ sender: UISegmentedControl) {
        let selectedType = workTypeSegmentedControl.titleForSegment(at: workTypeSegmentedControl.selectedSegmentIndex)
        if selectedType == "FLY" || selectedType == "TVL" {
            setupFlyTVLUI()
        } else {
            setupOtherUI()
        }
        addSaveButton()
    }
    
    // item 검증 함수: 반드시 2글자 영어 대문자 + 3글자 또는 4글자의 숫자 (예: KE123, KE1234)
    func isValidItem(_ item: String) -> Bool {
        let pattern = "^[A-Z]{2}\\d{3,4}$"
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: item)
    }
    
    @objc func saveTapped() {
        let outputDateFormatter = DateFormatter()
        outputDateFormatter.dateFormat = "dd-MMM-yyyy"
        outputDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        func isValidTime(_ time: String) -> Bool {
            // 시간은 반드시 HH:MM 형식 (00:00 ~ 23:59)
            let timeRegex = "^([01]\\d|2[0-3]):([0-5]\\d)$"
            return NSPredicate(format: "SELF MATCHES %@", timeRegex).evaluate(with: time)
        }
        
        func isValidAirportCode(_ code: String) -> Bool {
            // 공항 코드는 반드시 3글자 대문자 (IATA)
            let codeRegex = "^[A-Z]{3}$"
            return NSPredicate(format: "SELF MATCHES %@", codeRegex).evaluate(with: code)
        }
        
        let selectedType = workTypeSegmentedControl.titleForSegment(at: workTypeSegmentedControl.selectedSegmentIndex) ?? "FLY"
        var schedule: [String: String] = [:]
        if selectedType != "OTHER" {
            schedule["WorkType"] = selectedType
        }
        
        if selectedType == "FLY" || selectedType == "TVL" {
            let depDate = depDatePicker.date
            let arrDate = arrDatePicker.date
            schedule["DepDate"] = outputDateFormatter.string(from: depDate)
            schedule["ArrDate"] = outputDateFormatter.string(from: arrDate)
            
            // 공항 코드 검사 (반드시 IATA 3글자, 영어 대문자)
            guard let depAp = depApTextField.text?.uppercased(), isValidAirportCode(depAp) else {
                showAlert(title: "Invalid Airport", message: "Enter a valid departure airport code (3-letter IATA).")
                return
            }
            guard let arrAp = arrApTextField.text?.uppercased(), isValidAirportCode(arrAp) else {
                showAlert(title: "Invalid Airport", message: "Enter a valid arrival airport code (3-letter IATA).")
                return
            }
            schedule["DepAp"] = depAp
            schedule["ArrAp"] = arrAp
            
            // Item 검증: 반드시 영어 대문자 2글자와 숫자 3글자 또는 4글자 (예: KE123, KE1234)
            if let item = itemTextField.text, !item.isEmpty {
                let itemUpper = item.uppercased()
                if isValidItem(itemUpper) {
                    schedule["Item"] = itemUpper
                } else {
                    showAlert(title: "Invalid Item", message: "Item must be 2 uppercase letters followed by 3 or 4 digits (e.g., KE123 or KE1234).")
                    return
                }
            }
            
            // 시간은 반드시 HH:MM 형식
            guard let depTime = depStnTimeTextField.text, isValidTime(depTime) else {
                showAlert(title: "Invalid Time", message: "Enter a valid departure time (HH:mm).")
                return
            }
            guard let arrTime = arrStnTimeTextField.text, isValidTime(arrTime) else {
                showAlert(title: "Invalid Time", message: "Enter a valid arrival time (HH:mm).")
                return
            }
            schedule["DepStnTime"] = depTime
            schedule["ArrStnTime"] = arrTime
            
            // 비행시간과 근무시간은 사용자가 입력하면 HH:MM 형식이어야 함.
            if let flyingHours = flyingHoursTextField.text, !flyingHours.isEmpty {
                if isValidTime(flyingHours) {
                    schedule["FlyingHours"] = flyingHours
                } else {
                    showAlert(title: "Invalid Time", message: "Enter valid Flying Hours (HH:mm).")
                    return
                }
            }
            if let dutyHours = dutyHoursTextField.text, !dutyHours.isEmpty {
                if isValidTime(dutyHours) {
                    schedule["DutyHours"] = dutyHours
                } else {
                    showAlert(title: "Invalid Time", message: "Enter valid Duty Hours (HH:mm).")
                    return
                }
            }
        } else {
            // OTHER 타입인 경우
            let startDate = startDatePicker.date
            let endDate = endDatePicker.date
            schedule["DepDate"] = outputDateFormatter.string(from: startDate)
            schedule["DutyDebriefDate"] = outputDateFormatter.string(from: endDate)
            
            // Activity는 제한 없이 입력받음 (대문자로 저장)
            if let activity = activityTextField.text, !activity.isEmpty {
                 schedule["Activity"] = activity.uppercased()
            }
            
            // 시작 시간(근무 시작시간)은 HH:MM 형식인지 검증
            guard let startTime = dutyReportTextField.text, isValidTime(startTime) else {
                 showAlert(title: "Invalid Time", message: "Enter a valid start time (HH:mm).")
                 return
            }
            schedule["DutyReport"] = startTime
            
            // 종료 시간(근무 종료시간)도 HH:MM 형식인지 검증
            guard let endTime = dutyDebriefTextField.text, isValidTime(endTime) else {
                 showAlert(title: "Invalid Time", message: "Enter a valid end time (HH:mm).")
                 return
            }
            let dayDiff = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
            schedule["DutyDebrief"] = dayDiff > 0 ? "\(endTime)(+\(dayDiff))" : endTime
        }

        
        // 스케줄 저장: UserDefaults에 저장
        var savedSchedules = [String: [[String: String]]]()
        if let data = UserDefaults.standard.data(forKey: schedulesUserDefaultsKey) {
            do {
                savedSchedules = try JSONDecoder().decode([String: [[String: String]]].self, from: data)
            } catch {
                print("스케줄 로드 실패: \(error)")
            }
        }
        if let depDateKey = schedule["DepDate"] {
            savedSchedules[depDateKey, default: []].append(schedule)
        }
        do {
            let encodedData = try JSONEncoder().encode(savedSchedules)
            UserDefaults.standard.set(encodedData, forKey: schedulesUserDefaultsKey)
            print("Saved schedule: \(savedSchedules)")
        } catch {
            print("스케줄 저장 실패: \(error)")
        }
        
        // 저장 완료 후 알림창을 띄우고 팝업 닫기
        let alert = UIAlertController(title: "Success", message: "Schedule saved successfully.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            self.dismiss(animated: true, completion: nil)
        })
        present(alert, animated: true, completion: nil)
    }
    
    // MARK: - Alert Helper
    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title,
                                      message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
}
