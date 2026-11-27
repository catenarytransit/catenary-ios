//
//  Catenary_WidgetKitLiveActivity.swift
//  Catenary WidgetKit
//
//  Created by David Pilarčík on 27.11.2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct Catenary_WidgetKitAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct Catenary_WidgetKitLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: Catenary_WidgetKitAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension Catenary_WidgetKitAttributes {
    fileprivate static var preview: Catenary_WidgetKitAttributes {
        Catenary_WidgetKitAttributes(name: "World")
    }
}

extension Catenary_WidgetKitAttributes.ContentState {
    fileprivate static var smiley: Catenary_WidgetKitAttributes.ContentState {
        Catenary_WidgetKitAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: Catenary_WidgetKitAttributes.ContentState {
         Catenary_WidgetKitAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: Catenary_WidgetKitAttributes.preview) {
   Catenary_WidgetKitLiveActivity()
} contentStates: {
    Catenary_WidgetKitAttributes.ContentState.smiley
    Catenary_WidgetKitAttributes.ContentState.starEyes
}
