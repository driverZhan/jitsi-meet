/*
 * Copyright @ 2025-present 8x8, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import CoreSpotlight
import Intents
import MobileCoreServices
import UIKit

import JitsiMeetSDK


@objcMembers
class ViewController: UIViewController {
    
    var meet: JitsiMeetView!
    
    lazy var main: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .red
        return view
    }()
    
    lazy var strip: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .orange
        return view
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitle("开始", for: .normal)
        view.addSubview(btn)
        btn.backgroundColor = .systemCyan
        btn.addTarget(self, action: #selector(self.start), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 100),
            btn.heightAnchor.constraint(equalToConstant: 100),
            btn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            btn.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        

//        
//        
//        
//        
//        let jitsiView = JitsiMeetView(frame: UIScreen.main.bounds)
////        view.addSubview(jitsiView)
//        jitsiView.delegate = self
//        jitsiView.join(JitsiMeet.sharedInstance().getInitialConferenceOptions())
//        meet = jitsiView
//        meet.setAvatarHidden(true)
        
    }
    
    func start() {
        let meetVc = MeetController()
        meetVc.modalPresentationStyle  = .fullScreen
        present(meetVc, animated: true)
    }
    
    // MARK: - Helper Methods
    
    func terminate() {
        guard let view = self.view as? JitsiMeetView else { return }
        view.leave()
    }
}


extension ViewController: @preconcurrency JitsiMeetViewDelegate {

    // MARK: - Private Helper Methods
    
    private func onJitsiMeetViewDelegateEvent(_ name: String, withData data: [AnyHashable: Any]?) {
        NSLog("[%@:%d] JitsiMeetViewDelegate %@ %@", #file, #line, name, data ?? [:])
        
        #if DEBUG
        assert(Thread.isMainThread, "JitsiMeetViewDelegate \(name) method invoked on a non-main thread")
        #endif
    }

    // MARK: - JitsiMeetViewDelegate
    
    func conferenceJoined(_ data: [AnyHashable: Any]) {
        onJitsiMeetViewDelegateEvent("CONFERENCE_JOINED", withData: data)
        
        // Register a NSUserActivity for this conference so it can be invoked as a Siri shortcut.
        // Must match the one defined in Info.plist
        let userActivity = NSUserActivity(activityType: "org.jitsi.JitsiMeet.ios.conference")
        
        if let urlStr = data["url"] as? String,
           let url = URL(string: urlStr),
           let conference = url.pathComponents.last {
            
            userActivity.title = "Join \(conference)"
            userActivity.suggestedInvocationPhrase = "Join my Jitsi meeting"
            userActivity.userInfo = ["url": urlStr]
            userActivity.isEligibleForSearch = true
            userActivity.isEligibleForPrediction = true
            userActivity.persistentIdentifier = urlStr
            
            // Subtitle
            let attributes = CSSearchableItemAttributeSet(contentType: UTType.item)
            attributes.contentDescription = urlStr
            userActivity.contentAttributeSet = attributes
            
            self.userActivity = userActivity
            userActivity.becomeCurrent()
        }
        
    
    }
    
    func ready(toClose data: [AnyHashable: Any]) {
        onJitsiMeetViewDelegateEvent("READY_TO_CLOSE", withData: data)
    }
    
    func participantViewReady(_ data: [AnyHashable : Any]!) {
        guard let info = data as? [String: Any] else { return }
        print("custom delegate participantViewReady  \(String(describing: data))");
        if let participantId = info["participantId"] as? String, let isLocal: Bool = info["isLocal"] as? Bool {

            if (isLocal) {
                meet.detachParticipantView(participantId, container: strip) { view in
                    guard view != nil else {
                        print("custom delegate detach 失败: \(participantId)  isLocal:\(isLocal)")
                        return
                    }
                }
            }else {
                meet.detachParticipantView(participantId, container: main) { view in
                    guard view != nil else {
                        print("custom delegate detach 失败: \(participantId)  isLocal:\(isLocal)")
                        return
                    }
                }
            }
        }
        
    }
    
    
    func videoMutedChanged(_ data: [AnyHashable : Any]!) {
        print("custom delegate videoMutedChanged  \(String(describing: data))");
    }
    
    func audioMutedChanged(_ data: [AnyHashable : Any]!) {
        print("custom delegate audioMutedChanged  \(String(describing: data))");
    }
    
    func printViewIdenti(_ view: UIView) {
        print("custom delegate  accessibilityIdentifier = \(String(describing: view.accessibilityIdentifier))")
    }
    
}
