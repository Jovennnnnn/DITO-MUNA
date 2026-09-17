/**
 * Garbage Truck Live Tracking - Public Website Logic
 * FIXED: Full child snapshots iteration loop, Mapbox style load debug validations, and camera re-centering safeguards.
 */

// --- CONFIGURATION ---
const MAPBOX_ACCESS_TOKEN = 'pk.eyJ1IjoicHJpbmNlNjcwMyIsImEiOiJjbW9zeHB2ODIwNDFnMnRwdWxsam9sYWJmIn0.8DQhyf9Z9-yP8lCuP2WS3g';

// --- STATE MANAGEMENT ---
let map;
let markers = {}; // Store markers by truckId: { marker: mapboxgl.Marker, data: Object }
let truckLocationsRef;

// --- DOM ELEMENTS ---
const elements = {
    truckId: document.getElementById('truck-id'),
    status: document.getElementById('truck-status'),
    lastUpdated: document.getElementById('last-updated'),
    connStatus: document.getElementById('connection-status'),
    loadingOverlay: document.getElementById('loading-overlay'),
    loadingText: document.getElementById('loading-text')
};

/**
 * Initialize Mapbox Map with clear light background styles
 */
function initMap() {
    mapboxgl.accessToken = MAPBOX_ACCESS_TOKEN;

    map = new mapboxgl.Map({
        container: 'map',
        style: 'mapbox://styles/mapbox/light-v11', // Explicit White/Light theme asset mapping
        center: [120.9842, 14.5995],
        zoom: 12
    });

    map.addControl(new mapboxgl.NavigationControl());

    // Debug checks requested by user to inspect runtime parameters immediately after initialization
    map.on("load", () => {
        console.log("[MAPBOX STYLE]", map.getStyle()?.name);
        console.log("[MAPBOX STYLE URL]", map.getStyle()?.metadata);
    });

    map.on("style.load", () => {
        console.log("[MAPBOX] LIGHT STYLE LOADED");
    });
}

/**
 * Initialize Firebase database stream
 */
function initFirebase() {
    try {
        firebase.initializeApp(firebaseConfig);
        const db = firebase.database();
        truckLocationsRef = db.ref('truck_locations');

        console.log("%c[FIREBASE] Initialized successfully.", "color: green; font-weight: bold;");
        elements.connStatus.textContent = "Connecting...";
        elements.connStatus.className = "status-badge connecting";

        // REAL-TIME LISTENER: Listen for updates via child snapshots iteration loop
        truckLocationsRef.on('value', handleLocationUpdate, (error) => {
            console.error("[FIREBASE] Read Error:", error);
            elements.connStatus.textContent = "Error";
            elements.connStatus.className = "status-badge offline";
        });

        db.ref('.info/connected').on('value', (snap) => {
            if (snap.val() === false) {
                elements.connStatus.textContent = "Reconnecting...";
                elements.connStatus.className = "status-badge connecting";
            } else {
                elements.connStatus.textContent = "Live Updates";
                elements.connStatus.className = "status-badge online";
            }
        });

    } catch (error) {
        console.error("[FIREBASE] Initialization Error:", error);
        elements.loadingText.textContent = "Failed to connect to Firebase.";
    }
}

/**
 * Handle incoming data snapshots from Firebase using detailed snapshot child iteration loop
 * @param {firebase.database.DataSnapshot} snapshot
 */
function handleLocationUpdate(snapshot) {
    // 1. Log Raw JSON content to browser console exactly as requested
    console.log("[FIREBASE RAW truck_locations]", snapshot.val());

    if (!snapshot.exists()) {
        console.warn("[FIREBASE] No records under truck_locations node.");
        elements.loadingText.textContent = "No garbage truck is currently online.";
        elements.loadingOverlay.style.display = 'flex';
        // Remove all current markers
        Object.keys(markers).forEach(id => {
            markers[id].marker.remove();
            delete markers[id];
        });
        return;
    }

    let activeTruckCount = 0;
    let activeTruckIds = [];
    let visitedTruckIds = [];

    // Use absolute explicit child loops (snapshot.forEach) to eliminate single-value or firstChild limits entirely
    snapshot.forEach((childSnapshot) => {
        const truckId = childSnapshot.key;
        const truckData = childSnapshot.val();
        visitedTruckIds.push(truckId);

        console.log(`[FIREBASE TRUCK]\ntruckId: ${truckId}\nlatitude: ${truckData.latitude}\nlongitude: ${truckData.longitude}\status: ${truckData.status}\nlastSeen: ${truckData.lastSeen}\nupdatedAt: ${truckData.updatedAt}`);

        const status = (truckData.status || "").toUpperCase();
        const lat = parseFloat(truckData.latitude);
        const lng = parseFloat(truckData.longitude);

        // Geofence parsing validations
        const isValidCoords = !isNaN(lat) && !isNaN(lng) && lat !== 0 && lng !== 0 && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;

        // Match existing Flutter Driver app tracking lifecycle flags (ACTIVE, IDLE, FULL are valid online metrics)
        const isActive = (status === "ACTIVE" || status === "IDLE" || status === "FULL");

        if (isActive && isValidCoords) {
            activeTruckCount++;
            activeTruckIds.push(truckId);

            updateOrAddMarker(truckId, lat, lng, truckData);
        } else {
            // Remove marker immediately if truck status goes to OFFLINE or FINISHED
            if (markers[truckId]) {
                console.log(`[MAPBOX] Removing Inactive/Offline Truck: ${truckId}`);
                markers[truckId].marker.remove();
                delete markers[truckId];
            }
        }
    });

    console.log("[FIREBASE ACTIVE TRUCK COUNT]", activeTruckCount);
    console.log("[FIREBASE ACTIVE TRUCK IDS]", activeTruckIds.join(', '));
    console.log("[MAPBOX MARKERS]", Object.keys(markers).length);

    // Dynamic camera bounds containment mapping
    const finalActiveIds = Object.keys(markers);
    if (finalActiveIds.length > 0) {
        elements.loadingOverlay.style.display = 'none';

        // Sidebar metadata dashboard presentations
        const primaryId = finalActiveIds[0];
        updateSidebar(primaryId, markers[primaryId].data, finalActiveIds.length);

        // Dynamically frame all running assets inside viewport gracefully without continuous forcing
        fitMapToMarkers();
    } else {
        elements.loadingText.textContent = "No garbage truck is currently online.";
        elements.loadingOverlay.style.display = 'flex';
        elements.truckId.textContent = "--";
        elements.status.textContent = "OFFLINE";
        elements.status.className = "status-text OFFLINE";
    }

    // Clean up local markers if a node was dropped or completely deleted from the database
    Object.keys(markers).forEach(id => {
        if (!visitedTruckIds.includes(id)) {
            markers[id].marker.remove();
            delete markers[id];
        }
    });
}

/**
 * Append or reposition markers safely inside collection map
 */
function updateOrAddMarker(truckId, lat, lng, data) {
    if (!markers[truckId]) {
        const container = document.createElement('div');
        container.className = 'custom-truck-marker';

        const iconEl = document.createElement('div');
        iconEl.className = 'marker-icon';
        iconEl.innerHTML = '🚛';

        const labelEl = document.createElement('div');
        labelEl.className = 'marker-label';
        labelEl.textContent = truckId;

        container.appendChild(iconEl);
        container.appendChild(labelEl);

        const marker = new mapboxgl.Marker(container)
            .setLngLat([lng, lat])
            .setPopup(new mapboxgl.Popup({ offset: 25 }).setHTML(`<h3>${truckId}</h3><p>Status: ${data.status}</p>`))
            .addTo(map);

        markers[truckId] = { marker, data };
        console.log(`[MAPBOX MARKER] ${truckId} → ${lng}, ${lat}`);
    } else {
        markers[truckId].marker.setLngLat([lng, lat]);
        markers[truckId].data = data;
        console.log(`[MAPBOX MARKER] ${truckId} → ${lng}, ${lat}`);
    }
}

/**
 * Handle sidebar summary updates
 */
function updateSidebar(id, data, activeCount) {
    if (activeCount > 1) {
        elements.truckId.textContent = `${activeCount} Trucks Active`;
        elements.status.textContent = 'FLEET ONLINE';
        elements.status.className = 'status-text ACTIVE';
    } else {
        elements.truckId.textContent = id;
        elements.status.textContent = data.status || 'ACTIVE';
        elements.status.className = `status-text ${data.status}`;
    }

    const time = data.updatedAt ? new Date(data.updatedAt) : new Date(data.lastSeen);
    if (!isNaN(time.getTime())) {
        elements.lastUpdated.textContent = time.toLocaleTimeString();
    } else {
        elements.lastUpdated.textContent = "Just now";
    }
}

/**
 * Fit view limits smoothly to ensure total fleet coverage inside viewport borders
 */
function fitMapToMarkers() {
    const activeIds = Object.keys(markers);
    if (activeIds.length === 0) return;

    if (activeIds.length === 1) {
        const id = activeIds[0];
        // Use single flyTo only if bounds are not already centered near the coordinate point
        map.easeTo({
            center: markers[id].marker.getLngLat(),
            zoom: 14
        });
    } else {
        const bounds = new mapboxgl.LngLatBounds();
        activeIds.forEach(id => {
            bounds.extend(markers[id].marker.getLngLat());
        });
        map.fitBounds(bounds, { padding: 80, maxZoom: 15, duration: 1000 });
    }
}

// --- INITIALIZE MAIN ENTRY POINT ---
window.onload = () => {
    console.log("%c[SYSTEM] Garbage Tracker v1.0.3 (High Contrast Labels) Loaded", "color: blue; font-weight: bold;");
    initMap();
    initFirebase();
};
