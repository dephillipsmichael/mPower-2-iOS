//
//  TrackingViewController.swift
//  mPower2
//
//  Copyright © 2018 Sage Bionetworks. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
// 1.  Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// 2.  Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation and/or
// other materials provided with the distribution.
//
// 3.  Neither the name of the copyright holder(s) nor the names of any contributors
// may be used to endorse or promote products derived from this software without
// specific prior written permission. No license is granted to the trademarks of
// the copyright holders even if such marks are included in this software.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

import UIKit
import MotorControl
import Research
import ResearchUI
import BridgeApp

@IBDesignable
class TodayViewController: UIViewController {
    
    private let kTaskBrowserSegueIdentifier = "TaskBrowserSegue"
    private let kTableViewVerticalPadding = CGFloat(20.0).rsd_proportionalToScreenWidth()
    private let kTableViewTopInsetNoActionBar = CGFloat(40.0).rsd_proportionalToScreenWidth()
    private let kHeaderViewHeightSmall = CGFloat(160.0).rsd_proportionalToScreenWidth()
    private let kHeaderViewHeightMedium = CGFloat(180.0).rsd_proportionalToScreenWidth()
    private let kHeaderViewHeightLarge = CGFloat(210.0).rsd_proportionalToScreenWidth()

    @IBOutlet weak var headerContentView: UIView!
    @IBOutlet weak var headerImageView: UIImageView!
    @IBOutlet weak var headerGreetingLabel: UILabel!
    @IBOutlet weak var headerMessageLabel: UILabel!
    @IBOutlet weak var actionBarView: UIView!
    @IBOutlet weak var actionBarTitleLabel: UILabel!
    @IBOutlet weak var actionBarDetailsLabel: UILabel!
    @IBOutlet weak var progressCircleView: ProgressCircleView!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var taskBrowserContainerView: UIView!
    @IBOutlet weak var taskBrowserTopConstraint: NSLayoutConstraint!
    @IBOutlet weak var headerViewBottomConstraint: NSLayoutConstraint!
    
    var taskBrowserVC: TaskBrowserViewController?
    var tableSetupDone = false
    var dragDistance: CGFloat = 0.0
    var taskBrowserVisible = true {
        didSet {
            updateTaskBrowserPosition(animated: true)
        }
    }
    
    var shouldShowSurvey : Bool {
        return surveyManager.hasSurvey && studyBurstManager.isCompletedForToday
    }
    
    var shouldShowActionBar : Bool {
        return !self.studyBurstManager.isCompletedForToday || surveyManager.hasSurvey
    }
    
    // MARK: View lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupView()
        
        // TODO: jbruhin 5-1-18 find better way to handle this, including for the other 3 main VCs
        let customTabBarItem:UITabBarItem = UITabBarItem(title: "Tracking",
                                                         image: UIImage(named: "TabTracking _selected")?.withRenderingMode(UIImageRenderingMode.alwaysOriginal),
                                                         selectedImage: UIImage(named: "TabTracking _selected"))
        tabBarItem = customTabBarItem
    }
    
    override func prepareForInterfaceBuilder() {
        super.prepareForInterfaceBuilder()
        setupView()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        if !tableSetupDone {
            // This must be done in viewDidLayoutSubviews() because we might be resizing
            // the UITableView.headerView and making other adjustments on the tableView.
            // We only want to call this once from this method.
            tableSetupDone = true
            updateTableViewIfNeeded()
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == kTaskBrowserSegueIdentifier,
            let taskBrowser = segue.destination as? TaskBrowserViewController {
            taskBrowser.delegate = self
            taskBrowserVC = taskBrowser
        }
    }
    
    // MARK: View setup

    func setupView() {
        
        // Initial setup.
        actionBarView.layer.cornerRadius = 4.0
        actionBarView.layer.masksToBounds = true
        actionBarView.backgroundColor = UIColor.primaryTintColor
        
        // set up view for initial state.
        self.updateActionBar()
        self.updateProgressCircle()
        self.updateWelcomeContent()
        
        // Add pan gesture to the task browser container.
        let pan = UIPanGestureRecognizer(target: self, action: #selector(dragTaskBrowser(sender:)))
        taskBrowserContainerView.addGestureRecognizer(pan)
        
        // TODO: syoung 05/21/2018 - figure out what this is doing and what notifications may change it's position.
        self.updateTaskBrowserPosition(animated: false)
        
        // Update the welcome whenever the user is returning to the app.
        NotificationCenter.default.addObserver(forName: .UIApplicationWillEnterForeground, object: nil, queue: OperationQueue.main) { (_) in
            self.updateWelcomeContent()
        }
        
        // Update the study burst or survey to show in the action bar when those change.
        let managers = [todayManager, studyBurstManager, surveyManager]
        managers.forEach {
            NotificationCenter.default.addObserver(forName: .SBAUpdatedScheduledActivities, object: $0, queue: OperationQueue.main) { (notification) in
                if let _ = notification.object as? TodayHistoryScheduleManager {
                    self.updateWelcomeContent()
                    self.tableView.reloadData()
                }
                self.updateActionBar()
                self.updateProgressCircle()
                self.updateTableViewIfNeeded()
            }
        }
    }
    
    func updateTaskBrowserPosition(animated: Bool) {
        dragDistance = 0.0
        taskBrowserTopConstraint.constant = taskBrowserTopDistanceWhen(visible: taskBrowserVisible)
        if animated {
            UIView.animate(withDuration: 0.25) {
                // If browser is not visible, tell the browser to hide the rule at the bottom of the selected tab
                self.taskBrowserVC?.showSelectionIndicator(visible: self.taskBrowserVisible)
                self.view.layoutIfNeeded()
            }
        }
    }
    
    func updateWelcomeContent() {
        
        // Change the content based on the time of day: morning, afternoon, evening and whether or not the user
        // has completed any tasks today
        
        let content: (imageName: String, greeting: String, message: String) = {
            let firstName = SBAParticipantManager.shared.studyParticipant?.firstName
            var imageName: String
            var greeting: String
            switch Date().timeRange() {
            case .morning:
                imageName = "WelcomeMorning"
                greeting = firstName == nil ?
                    Localization.localizedString("MORNING_WELCOME_GREETING") :
                    Localization.localizedStringWithFormatKey("MORNING_WELCOME_GREETING_TO_%@", firstName!)
            case .afternoon:
                imageName = "WelcomeAfternoon"
                greeting = firstName == nil ?
                    Localization.localizedString("AFTERNOON_WELCOME_GREETING") :
                    Localization.localizedStringWithFormatKey("AFTERNOON_WELCOME_GREETING_TO_%@", firstName!)
            case .evening, .night:
                imageName = "WelcomeEvening"
                greeting = firstName == nil ?
                    Localization.localizedString("EVENING_WELCOME_GREETING") :
                    Localization.localizedStringWithFormatKey("EVENING_WELCOME_GREETING_TO_%@", firstName!)
            }
            let message = todayManager.items.count > 0 ?
                Localization.localizedString("WELCOME_MESSAGE_SOME_TASKS_DONE") :
                Localization.localizedString("WELCOME_MESSAGE_NO_TASKS_DONE")

            return (imageName, greeting, message)
        }()
        
        headerImageView.image = UIImage(named: content.imageName)
        headerGreetingLabel.text = content.greeting
        headerMessageLabel.text = content.message
    }
    
    func updateActionBar() {

        // If we should not show it, then make it's height 0, otherwise remove
        // the height constraint
        let previousConstraint = actionBarView.rsd_constraint(for: .height, relation: .equal)
        if shouldShowActionBar {
            if let heightConstraint = previousConstraint {
                NSLayoutConstraint.deactivate([heightConstraint])
            }
            
            if shouldShowSurvey, let schedule = surveyManager.scheduledActivities.first {
                actionBarTitleLabel.text = schedule.activity.title
                actionBarDetailsLabel.text = schedule.activity.detail
            }
            else {
                actionBarTitleLabel.text = studyBurstManager.activityGroup!.title
                if let expiresOn = studyBurstManager.expiresOn {
                    updateStudyBurstExpirationTime(expiresOn)
                }
                else {
                    actionBarDetailsLabel.text = Localization.localizedStringWithFormatKey("ACTIVITIES_TO_DO_%@", NSNumber(value: studyBurstManager.totalActivitiesCount))
                }
            }
        }
        else if (previousConstraint == nil) {
            actionBarView.rsd_makeHeight(.equal, 0.0)
        }
    }
    
    func updateStudyBurstExpirationTime(_ expiresOn: Date) {

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.collapsesLargestUnit = false
        formatter.zeroFormattingBehavior = .pad
        formatter.allowsFractionalUnits = false
        formatter.unitsStyle = .positional
        let timeString = formatter.string(from: Date(), to: expiresOn)!
        
        let marker = "%@"
        let format = Localization.localizedString("PROGRESS_EXPIRES_%@")
        
        let mutableString = NSMutableString(string: format)
        let markerRange = mutableString.range(of: marker)
        mutableString.replaceCharacters(in: markerRange, with: timeString)
        let boldRange = NSRange(location: markerRange.location, length: (timeString as NSString).length)
        let attributedString = NSMutableAttributedString(string: mutableString as String)
        let fullRange = NSRange(location: 0, length: attributedString.length)
        
        let fontSize: CGFloat = 14
        let font = UIFont.italicSystemFont(ofSize: fontSize)
        attributedString.addAttribute(.font, value: font, range: fullRange)
        if let fontDescriptor = font.fontDescriptor.withSymbolicTraits([.traitItalic, .traitBold]) {
            let boldFont = UIFont(descriptor: fontDescriptor, size: fontSize)
            attributedString.addAttribute(.font, value: boldFont, range: boldRange)
        }
        actionBarDetailsLabel.attributedText = attributedString
        
        // Fire update in 1 second.
        let delay = DispatchTime.now() + .seconds(1)
        DispatchQueue.main.asyncAfter(deadline: delay) {
            if let expiresOn = self.studyBurstManager.expiresOn {
                self.updateStudyBurstExpirationTime(expiresOn)
            }
        }
    }
    
    func updateProgressCircle() {
        
        if shouldShowSurvey {
            progressCircleView.isHidden = false
            progressCircleView.progress = 0.5
            // TODO: syoung 05/21/2018 Get the health survey icon from Stockard
            let healthIcon = UIImage(named: "activitiesTaskIconSmall")
            progressCircleView.displayIcon(image: healthIcon)
        }
        else if studyBurstManager.hasStudyBurst {
            progressCircleView.isHidden = false
            if let day = studyBurstManager.dayCount {
                progressCircleView.displayDay(count: day)
            }
            progressCircleView.progress = studyBurstManager.progress
        }
        else {
            progressCircleView.isHidden = true
        }
    }
    
    private var _previousItemCount : Int?
    private var _previousShouldShowActionBar : Bool?
    
    func updateTableViewIfNeeded() {
        
        let itemCount = todayManager.items.count
        let shouldShowActionBar = self.shouldShowActionBar
        guard itemCount != _previousItemCount || shouldShowActionBar != _previousShouldShowActionBar else {
            return
        }
        _previousItemCount = itemCount
        _previousShouldShowActionBar = shouldShowActionBar
        
        // Based on the variable content - a visible action bar or completed tasks - we do the following:
        // If we don't have completed tasks, make the tableView.headerView.height equal to the tableView.bounds.height
        // because we want the content to be centered vertically visually. If we do have completed tasks, then
        // we make the tableView.headerView.height equal to a constant that varies based on the content we have.
        // We have to adjust the constraints on the headerContentView to either center vertically in its
        // superview, or pin the top and bottom to its superview. This will determine how big the image is,
        // among other things.
        
        func adjustHeaderView(to height: CGFloat) {
            if let headerView = tableView.tableHeaderView {

                var frame = headerView.frame
                if height != frame.size.height {
                    frame.size.height = height
                    headerView.frame = frame
                    tableView.tableHeaderView = headerView
                }
            }
        }
        
        if itemCount > 0 {
            let height = shouldShowActionBar ? kHeaderViewHeightSmall : kHeaderViewHeightMedium
            adjustHeaderView(to: height)
            if let heightConstraint = headerContentView.rsd_constraint(for: .height, relation: .equal) {
                NSLayoutConstraint.deactivate([heightConstraint])
            }
            
            // Inset the top of the tableView
            let inset = shouldShowActionBar ? kTableViewVerticalPadding : kTableViewTopInsetNoActionBar
            tableView.contentInset = UIEdgeInsets(top: inset, left: 0.0, bottom: 0.0, right: 0.0)
        }
        else {
            adjustHeaderView(to: tableView.bounds.height)
            let contentHeight = [tableView.bounds.height - (2 * kTableViewVerticalPadding), kHeaderViewHeightLarge].min()
            headerContentView.rsd_makeHeight(.equal, contentHeight ?? 0)
            
            // Inset the top of the tableView jto 0
            tableView.contentInset = UIEdgeInsets(top: 0.0, left: 0.0, bottom: 0.0, right: 0.0)
        }

        // Adjust our contentOffset to account for contentInset
        tableView.setContentOffset(CGPoint(x: 0, y: -1 * tableView.contentInset.top), animated: false)
        
        // Adjust headerView bottom constraint (the padding between bottom label and bottom of view)
        headerViewBottomConstraint.constant = kTableViewVerticalPadding
    }
    
    // MARK: Model
    
    let todayManager = DataSourceManager.shared.todayHistoryScheduleManager()
    let studyBurstManager = DataSourceManager.shared.studyBurstScheduleManager()
    let surveyManager = DataSourceManager.shared.surveyManager()
    
    // MARK: Actions
    @IBAction func actionBarTapped(_ sender: Any) {
        // TODO: jbruhin 5-1-18 implement
        presentAlertWithOk(title: "Not implemented yet.", message: "", actionHandler: nil)
    }
}

extension TodayViewController: UITableViewDelegate, UITableViewDataSource {
    // MARK: UITableView Datasource
    
    open func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    open func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return todayManager.items.count
    }
    
    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "TrackingTableViewCell", for: indexPath) as! TodayTableViewCell
        let item = todayManager.items[indexPath.row]
        cell.iconView.image = item.icon
        
        // TODO: syoung 05/21/2018 FIXME!!! This should be a button that shows the results associated with this count, but there isn't any UI for that.
        cell.countLabel.text = item.title
        
        return cell
    }
    
    // MARK: UITableView Delegate
    open func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // TODO: jbruhin 5-10-18 implement??
        presentAlertWithOk(title: "Should this do something??", message: "", actionHandler: nil)
    }
}

extension TodayViewController: TaskBrowserViewControllerDelegate {
    
    // MARK: TaskBrowserViewController management
    
    @objc func dragTaskBrowser(sender: UIPanGestureRecognizer) {
        
        if sender.state == .ended {
            updateTaskBrowserPosition(animated: true)
        }
        else {
            let translation = sender.translation(in: taskBrowserContainerView)
            let newDragDistance = dragDistance + translation.y
            let newPoint = taskBrowserTopDistanceWhen(visible: taskBrowserVisible) + newDragDistance
            
            if shouldDrag(dragPoint: newPoint) {
                
                if !taskBrowserVisible && shouldOpenTaskBrowser(dragPoint: newPoint) {
                    taskBrowserVisible = true
                    return
                }
                
                if taskBrowserVisible && shouldCloseTaskBrowser(dragPoint: newPoint) {
                    taskBrowserVisible = false
                    return
                }
                
                dragDistance = newDragDistance
                taskBrowserTopConstraint.constant = newPoint
                sender.setTranslation(CGPoint.zero, in: self.view)
            }
        }
    }
    
    func shouldOpenTaskBrowser(dragPoint: CGFloat) -> Bool {
        // If the drag point is more than 1/3 of the way from closed to open, then we open
        let contentHeight = taskBrowserHeight() - TaskBrowserViewController.tabsHeight()
        let triggerPoint = taskBrowserTopDistanceWhen(visible: true) + contentHeight * 2/3
        return dragPoint < triggerPoint
    }
    
    func shouldCloseTaskBrowser(dragPoint: CGFloat) -> Bool {
        // If the drag point is more than 1/3 of the way from open to closed, then we close
        let contentHeight = taskBrowserHeight() - TaskBrowserViewController.tabsHeight()
        let triggerPoint = taskBrowserTopDistanceWhen(visible: true) + contentHeight * 1/3
        return dragPoint > triggerPoint
    }
    
    func shouldDrag(dragPoint: CGFloat) -> Bool {
        // Don't drag if we've gone beyond our closed or open positions
        let closedPoint = taskBrowserTopDistanceWhen(visible: false)
        let openedPoint = taskBrowserTopDistanceWhen(visible: true)
        return dragPoint < closedPoint && dragPoint > openedPoint
    }
    
    func taskBrowserTopDistanceWhen(visible: Bool) -> CGFloat {
        return view.bounds.height - taskBrowserHeightWhen(visible: visible) - (tabBarController?.tabBar.bounds.height ?? 0.0)
    }
    
    func taskBrowserHeightWhen(visible: Bool) -> CGFloat {
        if visible {
            return taskBrowserHeight()
        }
        else {
            return TaskBrowserViewController.tabsHeight()
        }
    }
    
    func taskBrowserHeight() -> CGFloat {
        if let heightConstraint = taskBrowserContainerView.rsd_constraint(for: .height, relation: .equal) {
            return heightConstraint.constant
        }
        return 0.0
    }
    
    // MARK: TaskBrowserViewControllerDelegate
    func taskBrowserToggleVisibility() {
        taskBrowserVisible = !taskBrowserVisible
    }
    func taskBrowserTabSelected() {
        if !taskBrowserVisible {
            taskBrowserVisible = true
        }
    }
}

class TodayTableViewCell: UITableViewCell {
    
    // TODO: jbruhin 5-10-18 - optimize positioning of content for different screen sizes
    @IBOutlet weak var iconView: UIImageView!
    @IBOutlet weak var countLabel: UILabel!
    
}

extension RSDTaskInfoObject {
    var iconSmall: UIImage? {
        get {
            return UIImage(named: "\(self.identifier)TaskIconSmall")
        }
    }
    var pluralTerm: String {
        get {
            return Localization.localizedString("TASK_PLURAL_TERM_FOR_\(identifier.uppercased())")
        }
    }
}
