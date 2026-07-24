//
//  MLNMapView+VisibleFeaturesCompatibility.swift
//  catenary-ios
//
//  Compatibility overloads for the argument-label change in newer
//  MapLibre Native Swift interfaces.
//

import CoreGraphics
import Foundation
import MapLibre

extension MLNMapView {
    func visibleFeatures(
        in point: CGPoint,
        inStyleLayersWithIdentifiers styleLayerIdentifiers: Set<String>?,
        predicate: NSPredicate?
    ) -> [MLNFeature] {
        visibleFeatures(
            in: point,
            styleLayerIdentifiers: styleLayerIdentifiers,
            predicate: predicate
        )
    }

    func visibleFeatures(
        in rect: CGRect,
        inStyleLayersWithIdentifiers styleLayerIdentifiers: Set<String>?,
        predicate: NSPredicate?
    ) -> [MLNFeature] {
        visibleFeatures(
            in: rect,
            styleLayerIdentifiers: styleLayerIdentifiers,
            predicate: predicate
        )
    }
}
