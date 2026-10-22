import Foundation

func decode(_ json: String) throws -> PhotonFeature {
    let response = try JSONDecoder().decode(PhotonResponse.self, from: Data(json.utf8))
    precondition(response.type == "FeatureCollection")
    precondition(response.features.count == 1)
    return response.features[0]
}

do {
    let zurich = try decode("""
    {
      "type":"FeatureCollection",
      "features":[{
        "type":"Feature",
        "properties":{
          "osm_type":"R","osm_id":1682248,"osm_key":"place",
          "osm_value":"city","type":"city","name":"Zurich",
          "country":"Suisse",
          "extra":{"admin_level":"8"},
          "extent":[8.44,47.43,8.62,47.32]
        },
        "geometry":{"type":"Point","coordinates":[8.5410422,47.3744489]}
      }]
    }
    """)
    precondition(zurich.osmReference == PhotonOSMReference(osmClass: "relation", osmID: "1682248"))
    precondition(zurich.coordinate?.latitude == 47.3744489)
    precondition(zurich.properties.osmValue == "city")

    let irvine = try decode("""
    {
      "type":"FeatureCollection",
      "features":[{
        "type":"Feature",
        "properties":{
          "osm_type":"N","osm_id":12805631573,
          "osm_key":"information","osm_value":"board",
          "type":"house","name":"UC Irvine Welcome sign",
          "street":"Campus Drive","city":"Irvine"
        },
        "geometry":{"type":"Point","coordinates":[-117.8354836,33.6476585]}
      }]
    }
    """)
    precondition(irvine.osmReference == PhotonOSMReference(osmClass: "node", osmID: "12805631573"))
    precondition(irvine.properties.osmKey == "information")
    precondition(irvine.coordinate?.longitude == -117.8354836)

    guard let url = PhotonAPI.searchURL(query: "T&T + 東京", latitude: 33.65,
                                        longitude: -117.83, zoom: 13.6),
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        fatalError("Photon URL could not be constructed")
    }
    let parameters = Dictionary(uniqueKeysWithValues:
        (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    precondition(parameters["q"] == "T&T + 東京")
    precondition(parameters["lat"] == "33.65")
    precondition(parameters["lon"] == "-117.83")
    precondition(parameters["zoom"] == "14")
    precondition(parameters["location_bias_scale"] == "0.1")

    print("Photon decoding and URL tests passed")
} catch {
    fputs("Photon test failed: \(error)\n", stderr)
    exit(1)
}
