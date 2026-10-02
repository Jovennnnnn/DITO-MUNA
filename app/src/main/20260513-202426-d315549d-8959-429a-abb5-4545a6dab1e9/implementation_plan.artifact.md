# Implementation Plan - User Management UI Improvements

This plan outlines the changes to improve the Purok selection highlight and add a "Clear Filter" option to the calendar dialog in the User Management screen.

## Proposed Changes

### [Purok Selection Component]

#### [NEW] [bg_purok_item.xml](file:///C:/xampp/htdocs/Asia-repo1-main/app/src/main/res/drawable/bg_purok_item.xml)
- Create a new ripple drawable with `accent_blue` (#E3F2FD) as the highlight color.

```xml
<?xml version="1.0" encoding="utf-8"?>
<ripple xmlns:android="http://schemas.android.com/apk/res/android"
    android:color="#E3F2FD">
    <item android:id="@android:id/mask">
        <color android:color="#FFFFFF" />
    </item>
    <item>
        <selector>
            <item android:state_pressed="true">
                <shape>
                    <solid android:color="#E3F2FD" />
                </shape>
            </item>
            <item android:drawable="@android:color/transparent" />
        </selector>
    </item>
</ripple>
```

#### [item_purok_selection.xml](file:///C:/xampp/htdocs/Asia-repo1-main/app/src/main/res/layout/item_purok_selection.xml)
- Update the background to use `@drawable/bg_purok_item`.

```xml
-    android:background="?attr/selectableItemBackground"
+    android:background="@drawable/bg_purok_item"
```

---

### [Calendar Dialog Component]

#### [dialog_custom_calendar.xml](file:///C:/xampp/htdocs/Asia-repo1-main/app/src/main/res/layout/dialog_custom_calendar.xml)
- Add a "Clear Filter" button above the "Apply Filter" button.

```xml
+    <com.google.android.material.button.MaterialButton
+        android:id="@+id/btn_clear_filter"
+        android:layout_width="match_parent"
+        android:layout_height="56dp"
+        android:layout_marginTop="12dp"
+        android:backgroundTint="@color/white"
+        android:text="Clear Filter"
+        android:textColor="#2A7C8A"
+        app:strokeColor="#2A7C8A"
+        app:strokeWidth="1dp"
+        android:textAllCaps="false"
+        android:textSize="16sp"
+        app:cornerRadius="12dp" />
```

#### [UserManagementActivity.kt](file:///C:/xampp/htdocs/Asia-repo1-main/app/src/main/java/com/example/myapplication/UserManagementActivity.kt)
- Handle the `btn_clear_filter` click in `showCustomCalendarDialog()`.

```kotlin
        val btnClear = view.findViewById<Button>(R.id.btn_clear_filter)
        btnClear.setOnClickListener {
            startDate = null
            endDate = null
            tvDateRange.text = "All Time"
            filterList(etSearch.text.toString())
            dialog.dismiss()
        }
```

## Verification Plan

### Manual Verification
1.  **Purok Selection**:
    *   Open User Management.
    *   Click on the Purok filter.
    *   Touch any Purok item and verify it highlights in light blue.
2.  **Calendar Filter**:
    *   Open User Management.
    *   Click on the Date filter.
    *   Select a date range and apply.
    *   Open the Date filter again.
    *   Verify the "Clear Filter" button is present.
    *   Click "Clear Filter" and verify the filter is reset to "All Time" and the list is updated.
