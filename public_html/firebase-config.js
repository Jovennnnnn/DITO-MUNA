// FIREBASE WEB CONFIGURATION
// Replace the values below with your actual Firebase Web Config from the Firebase Console.
// Go to Firebase Console > Project Settings > General > Your Apps > Web App (Add one if not exists).

const firebaseConfig = {
    apiKey: "AIzaSyAMvvefK0z-cpBLdWQaNpRvDfGtqv0GFe4",
    authDomain: "garbagesis-78d39.firebaseapp.com",
    databaseURL: "https://garbagesis-78d39-default-rtdb.asia-southeast1.firebasedatabase.app",
    projectId: "garbagesis-78d39",
    storageBucket: "garbagesis-78d39.firebasestorage.app",
    messagingSenderId: "410975851749",
    appId: "1:410975851749:android:56415852013793e1b2300c"
};

// Export config for app.js
if (typeof module !== 'undefined' && module.exports) {
    module.exports = firebaseConfig;
}
