//
//  ToolsViewController.swift
//  KERoster
//
//  Created by 윤정섭 on 2025/02/12.
//

import UIKit

class ToolsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    // 도구 목록
    let tools = ["ColdTempCorrection", "OtherTool1", "OtherTool2"]
    
    // 스토리보드에서 연결된 테이블 뷰
    @IBOutlet weak var tableView: UITableView!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 네비게이션 바 제목 설정
        self.navigationItem.title = "TOOLS"
        
        // 테이블 뷰의 데이터 소스와 델리게이트 설정
        tableView.dataSource = self
        tableView.delegate = self
    }

    // MARK: - UITableViewDataSource

    // 테이블 뷰의 행 수
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tools.count
    }

    // 테이블 뷰 셀의 내용 설정
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // "ToolCell"을 재사용
        let cell = tableView.dequeueReusableCell(withIdentifier: "ToolCell", for: indexPath)
        cell.textLabel?.text = tools[indexPath.row]
        return cell
    }

    // MARK: - UITableViewDelegate

    // 셀을 선택했을 때의 동작
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let selectedTool = tools[indexPath.row]
        if selectedTool == "ColdTempCorrection" {
            navigateToColdTempCorrection()
        }
    }

    // ColdTempCorrection 화면으로 이동
    func navigateToColdTempCorrection() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let correctionVC = storyboard.instantiateViewController(withIdentifier: "ColdTempCorrectionViewController") as? ColdTempCorrectionViewController {
            navigationController?.pushViewController(correctionVC, animated: true)
        }
    }
}
