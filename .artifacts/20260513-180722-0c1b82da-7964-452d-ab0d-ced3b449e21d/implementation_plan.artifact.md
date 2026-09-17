# Implementation Plan - GPS Tracking, Driver Status, and Trail Cleanup

This plan addresses issues with driver visibility, status updates, and visual glitches (spider-webbing) in the GPS tracking history.

## User Review Required

> [!IMPORTANT]
> - **Automatic Driver Activation**: I will implement automatic activation of the `LocationUpdateService` when a driver enters their dashboard.
> - **GPS Trail Cleanup**: I will implement aggressive filtering for jitter, accuracy checks, and timestamp sorting to fix the "messy" lines shown in the screenshots.

## Proposed Changes

### Driver Application

#### [LocationUpdateService.kt](file:///C:/xampp/htdocs/Asia-repo1-main/app/src/main/java/com/example/myapplication/network/LocationUpdateService.kt)

- **Accuracy Check**: Ignore any location update with accuracy > 35 meters.
- **Sanity Check**: Ignore points at (0,0) or with extreme jumps (> 500m in one update).
- **Movement Threshold**: Increase `MIN_DISTANCE_METERS` from 3.0 to 5.0 to further reduce stationary jitter.

### Admin Application

#### [MapboxFragment.kt](file:///C:/xampp/htdocs/Asia-repo1-main/app/src/main/java/com/example/myapplication/fragments/MapboxFragment.kt)

- **Timestamp Sorting**: Explicitly sort `routePoints` by `timestamp` before drawing the heatmap to prevent "zig-zag" lines caused by out-of-order data.
- **Coordinate Validation**: Filter out points with `lat == 0.0` or `lng == 0.0`.
- **Visual Polish**:
    - Reduce `lineWidth` from 4.0 to 2.5.
    - Reduce `lineOpacity` from 0.7 to 0.4 for a cleaner "trail" look.
    - Implement a "Max History" limit (e.g., last 200 points) to maintain performance and reduce clutter.

---

## Verification Plan

### Manual Verification
1. **Trail Stability**:
   - Simulate a driver staying in one spot for 5 minutes.
   - Verify that the Admin app DOES NOT show a "spider web" of lines around the driver.
2. **Path Correctness**:
   - Move the driver in a clear path.
   - Verify that the history trail follows the path smoothly without jumping back and forth.
3. **Invalid Data Handling**:
   - (Optional/Internal) Verify that accidental 0,0 points or poor GPS signal areas don't corrupt the map view.
