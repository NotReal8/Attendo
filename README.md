# Face Attendance — Setup Guide

## Project Structure

```
lib/
  main.dart                          ← App entry, theme, startup router
  models/
    student.dart                     ← Student + embedding model
    attendance_record.dart           ← Attendance record model
    group.dart                       New grouping system
  services/
    database_service.dart            ← SQLite CRUD (students + attendance)
    face_service.dart                Onnx + SCRFD Detection handling
    enrollment_service.dart          ← One-time enrollment pipeline
    attendance_service.dart          ← Session logic + CSV now EXCEL export
    app_log.dart                     Handles app logs via screen.
    beacon_service.dart              Firebase handler.
    liveness_service.dart            Anti-spoof mechanism
    restore_service.dart             Account restoration
    stress_test.service.dart         Simulator for 1000 students, stress test.
    transfer_service.dart            Handles local data transfer.

  screens/
    home_screen.dart                 ← Home with two action cards
    enrollment_screen.dart           ← Progress screen (first launch only)
    attendance_screen.dart           ← Live camera + real-time recognition
    records_screen.dart              ← Past sessions, export to CSV
    group_form_screen.dart           Formation od Groups.
    main_shell.dart
    onboarding_screen.dart           Login system
    restore_progress_screen.dart     Progress bar
    roster_screen.dart               Student roster
    select_group_screen              Group selection
    settings_screen.dart             Settings
  

assets/
  students/
    redundant.

  models/
    w600k_mbf.onnx                   Onnx handler.
    det_500m.onnx                    SCRFD model.
    best_model_quantized.onnx        Anti-spoof system.

android/
  app/
    build.gradle                     ← minSdk 24, noCompress tflite
    src/main/
      AndroidManifest.xml            ← CAMERA permission
      res/xml/file_paths.xml         ← FileProvider paths for share_plus
  build.gradle                       ← Project-level gradle
```

---

## Step 1 — Onboarding

Download the app and login using gievn credentials.
If account already exists, data will be restored automatically.
Local data transfer also permitted.

---

## Step 2 — Add student (enrollment)

1. Navigate to student roster, or register through home screen.
2. Input student's name and roll number.
3. Take or collect atleast one clear, well-lit photo of student (face clearly visible). This is auto captured.
4. Save the screen.
5. Add student into required domain as needed.

**Photo guidelines:**
- Photo auto-captured.
- Face should be centred, not obstructed
- One face per image
- Good, even lighting; avoid harsh shadows or glares.
- Avoid sunglasses, masks, or extreme angles

---

## Step 3 — Take Attendance

1. Navigate to home screen to take attendance.
2. Select domain.
3. Let the app load the camera, if the screen freezes, the app will automatically reload the camera.
4. Student presents face to camera (front or back) to mark attendance.
5. Save and Done. 

---

## Step 4 — Check Attendance Records

1. Navigate to record, select year, month, date and session.
2. Select timestamp, and edit data if needed.
3. Reload roster if needed.
4. Export data to excel via Export function.

---

## Step 5 — Admin Dashboard

1. Navigate to https://notreal8.github.io/GIFT_DB/#
2. Login using given credentials to view data.

---

## Exporting account data.

- Navigate to **Settings**
- Select export data

---

