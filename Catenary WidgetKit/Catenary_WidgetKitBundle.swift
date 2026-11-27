//
//  Catenary_WidgetKitBundle.swift
//  Catenary WidgetKit
//
//  Created by David Pilarčík on 27.11.2026.
//

import WidgetKit
import SwiftUI

@main
struct Catenary_WidgetKitBundle: WidgetBundle {
    var body: some Widget {
        Catenary_WidgetKit()
        Catenary_WidgetKitControl()
        Catenary_WidgetKitLiveActivity()
    }
}
