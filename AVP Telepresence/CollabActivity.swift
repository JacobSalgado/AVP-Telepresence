//
//  CollabActivity.swift
//  AVP Telepresence
//
//  Created by Research on 3/11/26.
//

import GroupActivities

struct CollabActivity : GroupActivity {
    static let activityIdentifier = "com.humanities.avpcollab.activity"
    
    var metadata : GroupActivityMetadata {
        var meta = GroupActivityMetadata()
        meta.title = "Collaboration Activity"
        meta.subtitle = "Join my spatial session"
        meta.type = .generic
        return meta
    }
}
