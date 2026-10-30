//
//  MeetController.swift
//  JitsiMeet
//
//  Created by .77 on 2026/8/6.
//  Copyright © 2026 Jitsi. All rights reserved.
//

import CoreSpotlight
import Intents
import MobileCoreServices
import UIKit

import JitsiMeetSDK

class MeetController: UIViewController {
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
    
    lazy var hangup: UIButton = {
        let btn = UIButton(type: .custom)
        btn.backgroundColor = .red
        btn.setImage(UIImage.init(systemName: "phone.down.fill"), for: .normal)
        btn.tintColor = .white
        btn.addTarget(self, action: #selector(self.leave(_:)), for: .touchUpInside)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    
    lazy var camera: UIButton = {
        let btn = UIButton(type: .custom)
        btn.backgroundColor = .red
        btn.setImage(UIImage.init(systemName: "video.fill"), for: .normal)
        btn.setImage(UIImage.init(systemName: "video.slash.fill"), for: .selected)
        btn.tintColor = .white
        btn.addTarget(self, action: #selector(self.videoMute(_:)), for: .touchUpInside)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    
    @objc func leave(_ sender: UIButton) {
        meet.hangUp()
    }
    
    @objc func videoMute(_ sender: UIButton) {
        sender.isSelected = !sender.isSelected
        meet.setVideoMuted(sender.isSelected)
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(main)
        view.addSubview(strip)
        view.addSubview(hangup)
        view.addSubview(camera)
        
        
        NSLayoutConstraint .activate([
            main.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            main.topAnchor.constraint(equalTo: view.topAnchor),
            main.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            main.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            strip.widthAnchor.constraint(equalToConstant: 100),
            strip.heightAnchor.constraint(equalToConstant: 150),
            strip.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            strip.topAnchor.constraint(equalTo: view.topAnchor, constant:130),
            
            camera.widthAnchor.constraint(equalToConstant: 50),
            camera.heightAnchor.constraint(equalToConstant: 50),
            camera.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -100),
            camera.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 50),
            
            hangup.widthAnchor.constraint(equalToConstant: 50),
            hangup.heightAnchor.constraint(equalToConstant: 50),
            hangup.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -100),
            hangup.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -50),
            
        ])
        
        
        
        
        
        
        
        
        
        let jitsiView = JitsiMeetView(frame: UIScreen.main.bounds)
        //        view.addSubview(jitsiView)
        jitsiView.delegate = self
        jitsiView.join(JitsiMeet.sharedInstance().getInitialConferenceOptions())
        meet = jitsiView
        meet.setAvatarHidden(true)
        
    }
    
    func terminate() {
        meet.leave()
    }
    
}

extension MeetController: @preconcurrency JitsiMeetViewDelegate {

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
    
    func conferenceTerminated(_ data: [AnyHashable : Any]!) {
        self.dismiss(animated: true, completion: nil)
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
