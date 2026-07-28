//
//  CatenaryColors.swift
//  catenary-ios
//

import SwiftUI
import UIKit

extension Color {
    static let catenaryBlue   = Color(red: 0/255.0, green: 171/255.0, blue: 155/255.0)
    static let railCategory   = Color.blue           // matches mapLibreView line 830
    static let metroCategory  = Color.purple         // line 841
    static let tramCategory   = Color.green          // line 852  (note: Metro/Tram tab uses Metro's purple)
    static let busCategory    = Color.catenaryBlue   // line 863
    static let otherCategory  = Color.orange         // line 874
}
extension UIColor {
    static let catenaryBlue   = UIColor(red: 0/255.0, green: 171/255.0, blue: 155/255.0, alpha: 1)
    static let railCategory   = UIColor.systemBlue
    static let metroCategory  = UIColor.systemPurple
    static let tramCategory   = UIColor.systemGreen
    static let busCategory    = UIColor.catenaryBlue
    static let otherCategory  = UIColor.systemOrange
}
