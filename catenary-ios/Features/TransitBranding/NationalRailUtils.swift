import Foundation

enum NationalRailUtils {
    static let chateauID = "nationalrailuk"

    struct AgencyInfo: Sendable {
        let name: String
        let iconName: String?
    }

    private static let agenciesByID: [String: AgencyInfo] = [
        "GW": AgencyInfo(name: "Great Western Railway", iconName: "GreaterWesternRailway.svg"),
        "GWR": AgencyInfo(name: "Great Western Railway", iconName: "GreaterWesternRailway.svg"),
        "SW": AgencyInfo(name: "South Western Railway", iconName: "SouthWesternRailway.svg"),
        "SN": AgencyInfo(name: "Southern", iconName: "SouthernIcon.svg"),
        "CC": AgencyInfo(name: "c2c", iconName: "c2c_logo.svg"),
        "LE": AgencyInfo(name: "Greater Anglia", iconName: nil),
        "CH": AgencyInfo(name: "Chiltern Railways", iconName: nil),
        "VT": AgencyInfo(name: "Avanti West Coast", iconName: nil),
        "HT": AgencyInfo(name: "Hull Trains", iconName: nil),
        "GN": AgencyInfo(name: "Great Northern", iconName: nil),
        "TL": AgencyInfo(name: "Thameslink", iconName: nil),
        "LO": AgencyInfo(name: "London Overground", iconName: "uk-london-overground.svg"),
        "AW": AgencyInfo(name: "Transport for Wales", iconName: nil),
        "SR": AgencyInfo(name: "ScotRail", iconName: nil),
        "GR": AgencyInfo(name: "London North Eastern Railway", iconName: nil),
        "EM": AgencyInfo(name: "East Midlands Railway", iconName: nil),
        "LM": AgencyInfo(name: "West Midlands Railway", iconName: nil),
        "SE": AgencyInfo(name: "Southeastern", iconName: nil),
        "XC": AgencyInfo(name: "CrossCountry", iconName: nil),
        "XR": AgencyInfo(name: "Elizabeth Line", iconName: "Elizabeth_line_roundel.svg")
    ]

    private static let agenciesByName: [String: AgencyInfo] = {
        var result: [String: AgencyInfo] = [:]
        for info in agenciesByID.values {
            result[normalize(info.name)] = info
        }
        result["gwr"] = agenciesByID["GWR"]
        return result
    }()

    static func agencyInfo(agencyID: String?, agencyName: String?) -> AgencyInfo? {
        if let agencyID, let value = agenciesByID[agencyID.uppercased()] {
            return value
        }
        if let agencyName, let value = agenciesByName[normalize(agencyName)] {
            return value
        }
        return nil
    }

    static func resolvedAgencyName(agencyID: String?, agencyName: String?) -> String? {
        agencyInfo(agencyID: agencyID, agencyName: agencyName)?.name
            ?? nonBlank(agencyName)
    }

    static func agencyIconURL(agencyID: String?, agencyName: String?) -> URL? {
        guard let iconName = agencyInfo(agencyID: agencyID, agencyName: agencyName)?.iconName else {
            return nil
        }
        return URL(string: "https://maps.catenarymaps.org/agencyicons/\(iconName)")
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}
