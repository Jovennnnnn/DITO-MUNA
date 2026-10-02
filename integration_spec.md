# Firebase Data Structure Integration Specification
**Project: Garbage Tracking System (Kotlin Android & Flutter Web)**

This document serves as the "contract" between the **Kotlin Driver App** and the **Flutter Web Admin Dashboard**. For the GPS and fleet monitoring to work automatically, the Kotlin app MUST save data to Firebase using the exact structure below.

---

## 1. Real-time GPS Tracking
**Firebase Node:** `truck_locations/{truck_id}`

The Flutter Web Admin listens to this node to move markers on the map.

### Required Fields (JSON Structure):
```json
{
  "truck_id": "GT-001",
  "driver_name": "Juan Dela Cruz",
  "latitude": 13.9414,
  "longitude": 121.1614,
  "status": "active",
  "speed": "25.5",
  "last_update": "2023-10-27 14:30:00"
}
```

### Constraints for Kotlin:
*   **Status Values:** Use lowercase strings: `"active"`, `"idle"`, or `"full"`.
*   **Data Types:** `latitude` and `longitude` should be **Double/Number**. `speed` should be a **String** or **Number**.
*   **Node Key:** Use a unique ID like `GT-001` or the driver's ID as the key under `truck_locations`.

---

## 2. Collection Progress Tracking
**Firebase Node:** `driver_routes/{unique_id}`

The Admin Dashboard calculates the "Collection Progress" bar using this data.

### Required Fields (JSON Structure):
```json
{
  "truck_id": "GT-001",
  "date": "2023-10-27",
  "route_status": "COMPLETED",
  "purok": "Purok 1"
}
```

### Constraints for Kotlin:
*   **Date Format:** Must be `YYYY-MM-DD` (e.g., `2023-10-27`). The Admin Web filters for "Today" using this exact format.
*   **Status Values:** Use uppercase `"COMPLETED"` or `"PENDING"`.

---

## 3. Real-time Notifications (Alerts)
**Firebase Node:** `notifications/{unique_push_id}`

The Admin Web shows pop-up snacks when a driver reports an issue.

### Required Fields (JSON Structure):
```json
{
  "title": "Truck Breakdown",
  "message": "Truck GT-001 has a flat tire at Purok 2",
  "type": "DRIVER_ISSUE",
  "isRead": false,
  "timestamp": 1698412200000
}
```

### Constraints for Kotlin:
*   **Type:** Use `"DRIVER_ISSUE"` for it to appear as a red alert in the Admin Web.
*   **isRead:** Set to `false` by default.

---

## 4. Collection Logs (For Analytics)
**Firebase Node:** `collection_logs/{unique_id}`

The Admin Analytics uses this to calculate "Average Collection Time" and "Distance Covered".

### Required Fields (JSON Structure):
```json
{
  "date": "2023-10-27",
  "zoneName": "Purok 1",
  "type": "ENTRY",
  "duration_minutes": 15,
  "distance_km": 2.5
}
```

### Constraints for Kotlin:
*   **type:** Use `"ENTRY"` or `"EXIT"`.
*   **duration_minutes**: Send this when a route is finished to update the Admin's efficiency charts.

---

## How to Verify:
1.  Open your **Kotlin Project**.
2.  Find the code where you use `FirebaseDatabase.getInstance().getReference()`.
3.  Check if the child names (e.g., `.child("latitude")`) match the names in this document exactly.
4.  If they match, the **Admin Web will automatically show the data** without any further changes.
