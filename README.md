# This is the Catenary ios implementation

## Contributors

- Charlie - SPŠE Hálova, Bratislava, Slovakia
- Chris Rios - University of California, Irvine - United States of America
- Kyler Chin - University of California, Irvine - United States of America
- snagglegrolop - United States of America
- Nathan Sheng - University of Toronto - Canada

## Trip planning

Open Directions from the map toolbar, or choose **As origin** / **As destination**
from a station or map item. The SwiftUI planner uses the same Edelweiss request
contract and defaults as catenary-compose (`471f579`). It supports place and stop
search, current location, decimal/DMS coordinates, map picking, departure/arrival
times, walking/cycling options, journey previews, and detailed transit legs.
Successful searches are retained on the device and restored when Directions opens.

On a machine with Swift installed, run `Tests/TripPlanner/run.sh` to check the API
contract, coordinate handling, shape clipping, and timeline presentation. The iOS
build workflow runs these checks before building the app for the simulator.

Manual simulator/device checks:

- Search for both endpoints, swap them, and change an endpoint while a request is
  running. The previous response must not replace the new search.
- Choose a map location with the fixed crosshair, then test station and POI
  shortcuts with location permission granted and denied.
- Compare departure and arrive-by queries, walking and cycling limits, no-results
  and network-error states. Open a journey and expand intermediate stops.
- Open Directions: endpoint search and results take over the full screen with an
  opaque background and plain controls. Scroll in both directions; the map drawer
  must not resize or intercept the gesture. Back/Home leave the planner.
- Open a transit journey: details take over the full screen, with the journey summary,
  star and map buttons at the top. Switch to Map and back to List; the same selected
  journey and summary remain. Back returns to the result list.
- Compare compact route badges, black mode icons in light mode, endpoint pearls,
  route rails, platforms, street distances and expandable intermediate stops against
  Compose. Check dark mode, landscape, VoiceOver and larger text sizes.
- Star a future journey, leave and reopen it: the star survives. Unstar it without
  leaving details. Past journeys cannot be newly starred.
- Scroll towards each result edge: earlier/later pages load once per gesture and
  preserve selection; prepending keeps the visible journey in view. Test failed
  pages and retries, fast endpoint edits, and exit during connection establishment.
  Opening Directions preconnects two WebSockets; each page consumes its own socket.
  Explicit backend errors remain authoritative; transport failures fall back to HTTP.
- Leave Directions: planner lines and endpoint markers disappear. Reopen it to
  restore the completed journey search.


### Development routing screenshots

The **iOS Screenshots** workflow runs on pull requests to `main`/`dev`, pushes to
`dev`, and manual dispatches (select the development branch). Its screenshot
artifact includes `routing/01-trip-planning.png` and three journey detail PNGs.
The run summary links to the artifact. These inject the live Santa Monica → UCLA request in
`Tests/TripPlanner/screenshot-route.json` (fixed departure epoch `1794598300`),
wait for routing completion and fullscreen presentation (map rendering is required
when the captured view actually shows the map), and
reopen the same saved results for ranks 1–3. Automatic pagination is suspended
for this capture so the ranks stay fixed. The simulator also swipes the fullscreen
results in both directions and verifies that the settled content offset changes
downward and then upward, rather than merely bouncing or resizing the drawer. A backend error or fewer than three
journeys fails the capture instead of producing loading/empty-state images.

Debug/screenshot builds accept `--ci-screenshot-planner results` together with
`--ci-screenshot-planner-query <absolute JSON path>` to start the search and `--ci-screenshot-planner 1` (or `2`/`3`) to reopen its journey details.
This capture uses a separate cached session and the normal SwiftUI planner,
route service, and map layers. Release builds without `SCREENSHOT_AUTOMATION`
do not expose these launch controls.

The JSON file contains a `route` WebSocket envelope. Its query fields and request
ID are sent through the normal planner transport; the displayed endpoints, time,
and options match it. To change the screenshot journey, edit this fixture. The
service still needs timetable coverage for its fixed date. Failures include app
stdout/stderr, readiness status (routing versus map rendering), and a diagnostic
screenshot in the artifact, rather than only a generic readiness timeout.
