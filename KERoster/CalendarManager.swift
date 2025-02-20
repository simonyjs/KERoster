//
//  CalendarManager.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/02/20.
//

import UIKit
import EventKit

/// 캘린더 관련 기능을 관리하는 클래스
class CalendarManager {
    let eventStore: EKEventStore
    var selectedCalendar: EKCalendar?
    
    init(eventStore: EKEventStore) {
        self.eventStore = eventStore
    }
    
    /// 사용 가능한 캘린더 목록과 "새 캘린더 생성" 옵션을 포함한 액션 시트를 표시하여 사용자가 원하는 캘린더를 선택하게 합니다.
    /// "새 캘린더 생성"을 선택하면 사용자에게 캘린더 이름을 입력받은 후 캘린더를 생성합니다.
    func presentCalendarSelection(from viewController: UIViewController, completion: @escaping (EKCalendar?) -> Void) {
        let calendars = eventStore.calendars(for: .event)
        let alert = UIAlertController(title: "Select Calendar", message: "Select the calendar you want to add the event.", preferredStyle: .actionSheet)
        
        for calendar in calendars {
            let action = UIAlertAction(title: calendar.title, style: .default) { _ in
                self.selectedCalendar = calendar
                self.debugLog("선택된 캘린더: \(calendar.title)")
                completion(calendar)
            }
            alert.addAction(action)
        }
        
        // 새 캘린더 생성 액션: 사용자에게 캘린더 이름 입력받기
        let createAction = UIAlertAction(title: "Create a new calendar", style: .default) { _ in
            let nameAlert = UIAlertController(title: "Create a new calendar", message: "Enter a calendar name.", preferredStyle: .alert)
            nameAlert.addTextField { textField in
                textField.placeholder = "Calendar Name."
            }
            nameAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
                completion(nil)
            }))
            nameAlert.addAction(UIAlertAction(title: "Create", style: .default, handler: { _ in
                if let name = nameAlert.textFields?.first?.text, !name.isEmpty {
                    self.createNewCalendar(withName: name) { newCalendar in
                        if let newCal = newCalendar {
                            self.selectedCalendar = newCal
                            self.debugLog("새로 생성된 캘린더: \(newCal.title)")
                        } else {
                            self.debugLog("자동 캘린더 생성 실패 - 기본 캘린더 사용")
                            self.selectedCalendar = self.eventStore.defaultCalendarForNewEvents
                        }
                        completion(self.selectedCalendar)
                    }
                } else {
                    self.debugLog("캘린더 이름이 입력되지 않음. 기본 캘린더를 사용합니다.")
                    let defaultCal = self.eventStore.defaultCalendarForNewEvents
                    self.selectedCalendar = defaultCal
                    completion(defaultCal)
                }
            }))
            viewController.present(nameAlert, animated: true, completion: nil)
        }
        alert.addAction(createAction)
        
        // 취소 액션
        alert.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in
            completion(nil)
        })
        
        // iPad 팝오버 설정
        if let popover = alert.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(x: viewController.view.bounds.midX,
                                        y: viewController.view.bounds.midY,
                                        width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        viewController.present(alert, animated: true, completion: nil)
    }
    
    /// 사용자가 입력한 이름으로 새 캘린더를 생성합니다.
    func createNewCalendar(withName name: String, completion: @escaping (EKCalendar?) -> Void) {
        // 로컬 소스부터 확인
        var source: EKSource? = eventStore.sources.first(where: { $0.sourceType == .local })
        
        // 로컬 소스가 없으면, iCloud, calDAV(예: Google) 또는 Exchange 소스를 사용
        if source == nil {
            if let iCloudSource = eventStore.sources.first(where: { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }) {
                source = iCloudSource
            }
            if source == nil {
                source = eventStore.sources.first(where: { $0.sourceType == .calDAV })
            }
            if source == nil {
                source = eventStore.sources.first(where: { $0.sourceType == .exchange })
            }
        }
        
        guard let validSource = source else {
            debugLog("캘린더 생성 실패: 사용 가능한 소스 없음")
            completion(nil)
            return
        }
        
        let newCalendar = EKCalendar(for: .event, eventStore: eventStore)
        newCalendar.title = name
        newCalendar.source = validSource
        
        do {
            try eventStore.saveCalendar(newCalendar, commit: true)
            debugLog("새 캘린더 생성 성공: \(newCalendar.title)")
            completion(newCalendar)
        } catch {
            debugLog("새 캘린더 생성 실패: \(error)")
            completion(nil)
        }
    }
    
    /// 같은 제목과 동일한 시간대(시작, 종료)가 있는 이벤트가 이미 존재하는지 확인합니다.
    func eventAlreadyExists(event: EKEvent) -> Bool {
        guard let calendar = event.calendar else { return false }
        let predicate = eventStore.predicateForEvents(withStart: event.startDate, end: event.endDate, calendars: [calendar])
        let existingEvents = eventStore.events(matching: predicate)
        // 이벤트 제목과 시작 시간이 동일한 이벤트를 중복으로 간주
        return existingEvents.contains { $0.title == event.title && $0.startDate == event.startDate }
    }
    
    /// 이벤트를 저장합니다.
    func saveEvent(event: EKEvent, completion: @escaping (Bool, Error?) -> Void) {
        if event.calendar == nil {
            if let calendar = selectedCalendar ?? eventStore.defaultCalendarForNewEvents {
                event.calendar = calendar
            } else {
                completion(false, NSError(domain: "CalendarManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "캘린더가 설정되어 있지 않습니다."]))
                return
            }
        }
        
        // 중복 이벤트 확인
        if eventAlreadyExists(event: event) {
            debugLog("중복 이벤트가 이미 존재합니다: \(event.title ?? "No Title") in \(event.calendar?.title ?? "N/A")")
            completion(true, nil)
            return
        }
        
        do {
            try eventStore.save(event, span: .thisEvent)
            debugLog("이벤트 저장 성공: \(event.title ?? "No Title") in \(event.calendar?.title ?? "N/A")")
            completion(true, nil)
        } catch {
            completion(false, error)
        }
    }
    
    // 디버그 로그 함수
    func debugLog(_ message: String) {
        print("[DEBUG] \(message)")
    }
}
