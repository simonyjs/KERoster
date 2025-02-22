//
//  ScheduleInputFormModifiedViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/02/22.
//

import UIKit

// MARK: - 공항 정보를 나타내는 구조체 (ApList.json 파일 구조)
// 기존의 Airport 타입과 충돌을 피하기 위해 KRAirport로 이름 변경
// JSON 예시:
// {
//      "IATA": "HPH",
//      "ICAO": "VVCI",
//      "utc_offset": 7.0,
//      "dst": false,
//      "name": "Cat Bi International Airport"
// }
struct KRAirport: Decodable {
    let IATA: String
    let ICAO: String
    let utc_offset: Double
    let dst: Bool
    let name: String
}

class ScheduleInputFormModifiedViewController: UIViewController, UITextFieldDelegate, UIPickerViewDelegate, UIPickerViewDataSource {
    
    // 달력에서 전달받은 선택 날짜 (Date 타입)
    var selectedDate: Date?
    
    // 수동 입력 스케줄 저장용 UserDefaults 키 (import된 스케줄과 분리)
    let manualSchedulesUserDefaultsKey = "manualSchedules"
    
    // ApList.json에 저장된 공항 정보를 [KRAirport] 배열로 저장
    var airportList: [KRAirport] = []
    
    // MARK: - UI Elements
    
    // 스크롤뷰: 키보드 등장 시 스크롤 가능하도록 함
    let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.backgroundColor = .systemBackground // 다크/라이트 모드 지원
        return sv
    }()
    
    // 모든 입력폼을 담을 메인 스택뷰
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
        control.setTitleTextAttributes([.foregroundColor: UIColor.label], for: .normal)
        return control
    }()
    
    // 타임존 선택 텍스트필드 (사용자가 ApList.json에 있는 IATA 공항 중 선택; OTHER 타입에만 필요)
    let timezoneTextField: UITextField = {
        let tf = UITextField()
        tf.placeholder = "Select Timezone Airport (e.g., GMP)"
        tf.borderStyle = .roundedRect
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()
    
    // 타임존 선택을 위한 UIPickerView
    let timezonePicker = UIPickerView()
    
    // MARK: - FLY/TVL 타입 전용 입력 UI
    let depDatePicker: UIDatePicker = {
        let picker = UIDatePicker()
        if #available(iOS 14.0, *) { picker.preferredDatePickerStyle = .inline }
        picker.datePickerMode = .date
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.backgroundColor = .secondarySystemBackground
        return picker
    }()
    
    let arrDatePicker: UIDatePicker = {
        let picker = UIDatePicker()
        if #available(iOS 14.0, *) { picker.preferredDatePickerStyle = .inline }
        picker.datePickerMode = .date
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.backgroundColor = .secondarySystemBackground
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
        picker.backgroundColor = .secondarySystemBackground
        return picker
    }()
    
    let endDatePicker: UIDatePicker = {
        let picker = UIDatePicker()
        if #available(iOS 14.0, *) { picker.preferredDatePickerStyle = .inline }
        picker.datePickerMode = .date
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.backgroundColor = .secondarySystemBackground
        return picker
    }()
    
    let activityTextField = UITextField()
    let dutyReportTextField = UITextField()        // Work start time
    let dutyDebriefTextField = UITextField()         // Work end time
    // OTHER 타입 추가 노트 입력 필드
    let noteTextField = UITextField()
    
    // MARK: - View LifeCycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        self.title = "Schedule Input"
        
        setupScrollView()
        setupMainStackView()
        configureSegmentedControl()
        
        // 타임존 선택 UI는 OTHER 타입일 때만 필요하므로 초기엔 숨김 처리
        // (나중에 workTypeChanged에서 OTHER 타입이면 추가합니다)
        
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
        
        // ApList.json 파일에서 공항 목록 로드 ([KRAirport]로 디코딩)
        airportList = loadAirportList() ?? []
        // 기본값을 GMP로 설정 (목록에 GMP가 있다면)
        if let index = airportList.firstIndex(where: { $0.IATA == "GMP" }) {
            timezonePicker.selectRow(index, inComponent: 0, animated: false)
            timezoneTextField.text = "GMP"
        } else {
            timezoneTextField.text = "GMP"
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
    
    // MARK: - ScrollView & StackView Setup
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
    
    // MARK: - Timezone Field Setup
    func setupTimezoneField() {
        timezonePicker.delegate = self
        timezonePicker.dataSource = self
        timezoneTextField.inputView = timezonePicker
        // 타임존 필드는 OTHER 타입에만 필요하므로, 여기서는 추가하지 않습니다.
    }
    
    // MARK: - Keyboard Handling
    @objc func keyboardWillShow(notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        scrollView.contentInset.bottom = keyboardFrame.height
        scrollView.verticalScrollIndicatorInsets.bottom = keyboardFrame.height
    }
    
    @objc func keyboardWillHide(notification: Notification) {
        scrollView.contentInset.bottom = 0
        scrollView.verticalScrollIndicatorInsets.bottom = 0
    }
    
    // MARK: - UI Setup Methods
    func configureSegmentedControl() {
        workTypeSegmentedControl.addTarget(self, action: #selector(workTypeChanged(_:)), for: .valueChanged)
        mainStackView.addArrangedSubview(workTypeSegmentedControl)
    }
    
    // Create a horizontal stack view with a label and a text field
    func createLabeledField(labelText: String, textField: UITextField) -> UIStackView {
        let label = UILabel()
        label.text = labelText
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .label
        label.widthAnchor.constraint(equalToConstant: 100).isActive = true
        
        textField.placeholder = labelText
        textField.borderStyle = .roundedRect
        textField.textColor = .label
        textField.backgroundColor = .secondarySystemBackground
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.heightAnchor.constraint(equalToConstant: 30).isActive = true
        
        let hStack = UIStackView(arrangedSubviews: [label, textField])
        hStack.axis = .horizontal
        hStack.spacing = 8
        return hStack
    }
    
    // Create a vertical stack view with a label and a date picker
    func createLabeledPicker(labelText: String, picker: UIDatePicker) -> UIStackView {
        let label = UILabel()
        label.text = labelText
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .label
        
        let vStack = UIStackView(arrangedSubviews: [label, picker])
        vStack.axis = .vertical
        vStack.spacing = 4
        return vStack
    }
    
    /// Setup input UI for FLY/TVL type
    func setupFlyTVLUI() {
        // 먼저 OTHER 타입용 타임존 필드가 있다면 제거 (FLY/TVL는 타임존이 필요 없음)
        if mainStackView.arrangedSubviews.contains(timezoneTextField) {
            mainStackView.removeArrangedSubview(timezoneTextField)
            timezoneTextField.removeFromSuperview()
        }
        // Remove all views except the segmented control
        for view in mainStackView.arrangedSubviews {
            if view !== workTypeSegmentedControl {
                mainStackView.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
        }
        mainStackView.addArrangedSubview(workTypeSegmentedControl)
        // Add FLY/TVL specific fields
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
    
    /// Setup input UI for OTHER type, including an additional note field and timezone field
    func setupOtherUI() {
        // For OTHER type, ensure the timezone field is visible.
        if !mainStackView.arrangedSubviews.contains(timezoneTextField) {
            // Insert timezone field below segmented control (at index 1)
            mainStackView.insertArrangedSubview(timezoneTextField, at: 1)
            // Also, set up the timezone field UI.
            setupTimezoneField()
        }
        // Remove all views except segmented control and timezone field
        for view in mainStackView.arrangedSubviews {
            if view !== workTypeSegmentedControl && view !== timezoneTextField {
                mainStackView.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
        }
        mainStackView.addArrangedSubview(workTypeSegmentedControl)
        // Ensure timezone field remains at index 1
        // Add OTHER type specific fields
        mainStackView.addArrangedSubview(createLabeledPicker(labelText: "Start Date", picker: startDatePicker))
        mainStackView.addArrangedSubview(createLabeledPicker(labelText: "End Date", picker: endDatePicker))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "Activity", textField: activityTextField))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "Start Time", textField: dutyReportTextField))
        mainStackView.addArrangedSubview(createLabeledField(labelText: "End Time", textField: dutyDebriefTextField))
        // Add note field for OTHER type schedules
        noteTextField.placeholder = "Enter additional note (optional)"
        noteTextField.borderStyle = .roundedRect
        noteTextField.translatesAutoresizingMaskIntoConstraints = false
        noteTextField.heightAnchor.constraint(equalToConstant: 30).isActive = true
        mainStackView.addArrangedSubview(createLabeledField(labelText: "Note", textField: noteTextField))
    }
    
    /// Add Save Schedule button
    func addSaveButton() {
        for view in mainStackView.arrangedSubviews {
            if let button = view as? UIButton, button.currentTitle == "Save Schedule" {
                mainStackView.removeArrangedSubview(button)
                button.removeFromSuperview()
            }
        }
        let saveButton = UIButton(type: .system)
        saveButton.setTitle("Save Schedule", for: .normal)
        saveButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
        saveButton.backgroundColor = .systemBlue
        saveButton.tintColor = .white
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
    
    // Validate item format: 2 uppercase letters and 3 to 4 digits (e.g., KE123, KE1234)
    func isValidItem(_ item: String) -> Bool {
        let pattern = "^[A-Z]{2}\\d{3,4}$"
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: item)
    }
    
    @objc func saveTapped() {
        let outputDateFormatter = DateFormatter()
        outputDateFormatter.dateFormat = "dd-MMM-yyyy"
        outputDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        func isValidTime(_ time: String) -> Bool {
            let timeRegex = "^([01]\\d|2[0-3]):([0-5]\\d)$"
            return NSPredicate(format: "SELF MATCHES %@", timeRegex).evaluate(with: time)
        }
        
        func isValidAirportCode(_ code: String) -> Bool {
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
            
            guard let depAp = depApTextField.text?.uppercased(), isValidAirportCode(depAp) else {
                showAlert(title: "Invalid Airport", message: "Please enter a valid departure airport code (3-letter IATA).", dismissOnOK: false)
                return
            }
            guard let arrAp = arrApTextField.text?.uppercased(), isValidAirportCode(arrAp) else {
                showAlert(title: "Invalid Airport", message: "Please enter a valid arrival airport code (3-letter IATA).", dismissOnOK: false)
                return
            }
            schedule["DepAp"] = depAp
            schedule["ArrAp"] = arrAp
            
            if let item = itemTextField.text, !item.isEmpty {
                let itemUpper = item.uppercased()
                if isValidItem(itemUpper) {
                    schedule["Item"] = itemUpper
                } else {
                    showAlert(title: "Invalid Item", message: "Item must consist of 2 uppercase letters and 3 to 4 digits (e.g., KE123 or KE1234).", dismissOnOK: false)
                    return
                }
            }
            
            guard let depTime = depStnTimeTextField.text, isValidTime(depTime) else {
                showAlert(title: "Invalid Time", message: "Please enter a valid departure time (HH:mm).", dismissOnOK: false)
                return
            }
            guard let arrTime = arrStnTimeTextField.text, isValidTime(arrTime) else {
                showAlert(title: "Invalid Time", message: "Please enter a valid arrival time (HH:mm).", dismissOnOK: false)
                return
            }
            schedule["DepStnTime"] = depTime
            schedule["ArrStnTime"] = arrTime
            
            if let flyingHours = flyingHoursTextField.text, !flyingHours.isEmpty {
                if isValidTime(flyingHours) {
                    schedule["FlyingHours"] = flyingHours
                } else {
                    showAlert(title: "Invalid Time", message: "Please enter valid Flying Hours (HH:mm).", dismissOnOK: false)
                    return
                }
            }
            if let dutyHours = dutyHoursTextField.text, !dutyHours.isEmpty {
                if isValidTime(dutyHours) {
                    schedule["DutyHours"] = dutyHours
                } else {
                    showAlert(title: "Invalid Time", message: "Please enter valid Duty Hours (HH:mm).", dismissOnOK: false)
                    return
                }
            }
        } else {
            // OTHER type handling
            let startDate = startDatePicker.date
            let endDate = endDatePicker.date
            schedule["DepDate"] = outputDateFormatter.string(from: startDate)
            schedule["DutyDebriefDate"] = outputDateFormatter.string(from: endDate)
            
            if let activity = activityTextField.text, !activity.isEmpty {
                schedule["Activity"] = activity.uppercased()
            }
            guard let startTime = dutyReportTextField.text, isValidTime(startTime) else {
                showAlert(title: "Invalid Time", message: "Please enter a valid start time (HH:mm).", dismissOnOK: false)
                return
            }
            schedule["DutyReport"] = startTime
            
            guard let endTime = dutyDebriefTextField.text, isValidTime(endTime) else {
                showAlert(title: "Invalid Time", message: "Please enter a valid end time (HH:mm).", dismissOnOK: false)
                return
            }
            let dayDiff = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
            schedule["DutyDebrief"] = dayDiff > 0 ? "\(endTime)(+\(dayDiff))" : endTime
            
            // Save additional note if provided
            if let note = noteTextField.text, !note.isEmpty {
                schedule["Note"] = note
            }
            // For OTHER type, also include timezone from the field
            let selectedTimezone = timezoneTextField.text ?? "GMP"
            schedule["TimeZoneIATA"] = selectedTimezone
        }
        
        // For FLY/TVL, timezone is determined by DEP/ARR so we don't include timezone field
        if selectedType == "FLY" || selectedType == "TVL" {
            schedule["TimeZoneIATA"] = ""
        }
        
        // Save manual schedules separately so that imported schedules are not overwritten
        var savedSchedules = [String: [[String: String]]]()
        if let data = UserDefaults.standard.data(forKey: manualSchedulesUserDefaultsKey) {
            do {
                savedSchedules = try JSONDecoder().decode([String: [[String: String]]].self, from: data)
            } catch {
                print("Failed to load manual schedules: \(error)")
            }
        }
        if let depDateKey = schedule["DepDate"] {
            savedSchedules[depDateKey, default: []].append(schedule)
        }
        do {
            let encodedData = try JSONEncoder().encode(savedSchedules)
            UserDefaults.standard.set(encodedData, forKey: manualSchedulesUserDefaultsKey)
            print("Saved manual schedules: \(savedSchedules)")
        } catch {
            print("Failed to save manual schedules: \(error)")
        }
        
        // Show success alert and dismiss the view controller automatically
        showAlert(title: "Success", message: "The schedule was saved successfully.", dismissOnOK: true)
    }
    
    // MARK: - UIPickerViewDataSource & Delegate Methods
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return airportList.count
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return airportList[row].IATA // Display IATA code
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        timezoneTextField.text = airportList[row].IATA
    }
    
    // MARK: - Load airport list (Decode ApList.json into [KRAirport])
    func loadAirportList() -> [KRAirport]? {
        guard let path = Bundle.main.path(forResource: "ApList", ofType: "json") else {
            print("Failed to find ApList.json path")
            return nil
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let airports = try JSONDecoder().decode([KRAirport].self, from: data)
            print("Successfully parsed ApList.json: \(airports.count) airports")
            return airports
        } catch {
            print("Failed to load ApList.json: \(error)")
            return nil
        }
    }
    
    // MARK: - Alert Helper with optional dismissal
    func showAlert(title: String, message: String, dismissOnOK: Bool) {
        let alert = UIAlertController(title: title,
                                      message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            if dismissOnOK {
                self.dismiss(animated: true, completion: nil)
            }
        }))
        present(alert, animated: true, completion: nil)
    }
}
