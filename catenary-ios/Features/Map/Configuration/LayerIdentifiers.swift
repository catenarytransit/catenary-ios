//
//  LayerIdentifiers.swift
//  catenary-ios
//

enum LayersPerCategory {

    static let Bus = BusCategory()
    static let Other = OtherCategory()
    static let IntercityRail = IntercityRailCategory()
    static let Metro = MetroCategory()
    static let Tram = TramCategory()
    static let TrajectoryBus = TrajectoryCategory(prefix: "trajectory-bus")
    static let TrajectoryMetro = TrajectoryCategory(prefix: "trajectory-metro")
    static let TrajectoryTram = TrajectoryCategory(prefix: "trajectory-tram")
    static let TrajectoryIntercityRail = TrajectoryCategory(prefix: "trajectory-intercityrail")
    static let TrajectoryOther = TrajectoryCategory(prefix: "trajectory-other")

    struct TrajectoryCategory {
        let Livedots: String
        let Labeldots: String

        init(prefix: String) {
            Livedots = "\(prefix)-livedots"
            Labeldots = "\(prefix)-labeldots"
        }
    }

    struct BusCategory {
        let Shapes = "bus-shapes"
        let LabelShapes = "bus-labelshapes"
        let Stops = "bus-stops"
        let LabelStops = "bus-labelstops"
        let Livedots = "bus-livedots"
        let Labeldots = "bus-labeldots"
        let Pointing = "bus-pointing"
        let PointingShell = "bus-pointingshell"
    }

    struct OtherCategory {
        let Shapes = "other-shapes"
        let LabelShapes = "other-labelshapes"
        let FerryShapes = "ferryshapes"
        let Stops = "other-stops"
        let LabelStops = "other-labelstops"
        let Livedots = "other-livedots"
        let Labeldots = "other-labeldots"
        let Pointing = "other-pointing"
        let PointingShell = "other-pointingshell"
    }

    struct IntercityRailCategory {
        let Shapes = "intercityrail-shapes"
        let LabelShapes = "intercityrail-labelshapes"
        let Stops = "intercityrail-stops"
        let LabelStops = "intercityrail-labelstops"
        let Livedots = "intercityrail-livedots"
        let Labeldots = "intercityrail-labeldots"
        let Pointing = "intercityrail-pointing"
        let PointingShell = "intercityrail-pointingshell"
    }

    struct MetroCategory {
        let Shapes = "metro-shapes"
        let LabelShapes = "metro-labelshapes"
        let Stops = "metro-stops"
        let LabelStops = "metro-labelstops"
        let Livedots = "metro-livedots"
        let Labeldots = "metro-labeldots"
        let Pointing = "metro-pointing"
        let PointingShell = "metro-pointingshell"
    }

    struct TramCategory {
        let Shapes = "tram-shapes"
        let LabelShapes = "tram-labelshapes"
        let Stops = "tram-stops"
        let LabelStops = "tram-labelstops"
        let Livedots = "tram-livedots"
        let Labeldots = "tram-labeldots"
        let Pointing = "tram-pointing"
        let PointingShell = "tram-pointingshell"
    }
}
