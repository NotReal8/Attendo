# Face Attendance — Setup Guide

## Project Structure

```
lib/
  main.dart                          ← App entry, theme, startup router
  models/
    student.dart                     ← Student + embedding model
    attendance_record.dart           ← Attendance record model
  services/
    database_service.dart            ← SQLite CRUD (students + attendance)
    face_embedding_service.dart      ← ML Kit detection + TFLite inference
    enrollment_service.dart          ← One-time enrollment pipeline
    attendance_service.dart          ← Session logic + CSV export
  screens/
    home_screen.dart                 ← Home with two action cards
    enrollment_screen.dart           ← Progress screen (first launch only)
    attendance_screen.dart           ← Live camera + real-time recognition
    records_screen.dart              ← Past sessions, export to CSV

assets/
  students/
    manifest.txt                     ← List of image filenames (YOU EDIT THIS)
    John Smith.jpg                   ← Student photos (YOU ADD THESE)
    Alice Johnson.png
    ...
  models/
    mobilefacenet.tflite             ← YOU MUST DOWNLOAD THIS (see below)

android/
  app/
    build.gradle                     ← minSdk 24, noCompress tflite
    src/main/
      AndroidManifest.xml            ← CAMERA permission + ML Kit meta-data
      res/xml/file_paths.xml         ← FileProvider paths for share_plus
  build.gradle                       ← Project-level gradle
```

---

## Step 1 — Download MobileFaceNet model

Download `mobilefacenet.tflite` from:
https://github.com/shaqian/tflite-models/raw/master/mobilefacenet.tflite

Place it at: `assets/models/mobilefacenet.tflite`

Model specs:
- Input:  [1, 112, 112, 3]  float32 (normalized to [-1, 1])
- Output: [1, 128]          float32 (face embedding vector)
- Size:   ~1.9 MB

---

## Step 2 — Add student photos

1. Take or collect one clear, well-lit photo of each student (face clearly visible).
2. Name the file exactly as you want the student's name to appear:
   - `John Smith.jpg`
   - `Priya Sharma.png`
3. Copy files into `assets/students/`
4. Open `assets/students/manifest.txt` and list every filename, one per line.

**Photo guidelines:**
- Minimum 200×200 pixels (larger is better)
- Face should be centred, not obstructed
- One face per image
- Good, even lighting; avoid harsh shadows
- Avoid sunglasses, masks, or extreme angles

---

## Step 3 — Update pubspec.yaml if needed

The assets block is already configured:
```yaml
flutter:
  assets:
    - assets/students/
    - assets/models/
```

---

## Step 4 — Install dependencies

```bash
flutter pub get
```

---

## Step 5 — Run on Android

```bash
flutter run
```

On first launch the app will:
1. Show the Enrollment screen
2. Automatically load each image from assets
3. Run ML Kit + MobileFaceNet on each image
4. Save the 128-d embedding to local SQLite
5. Navigate to Home screen

This happens **once only**. Subsequent launches go straight to Home.

---

## How recognition works at runtime

1. Camera stream starts (front camera preferred)
2. Every ~400ms a frame is grabbed
3. ML Kit detects faces in the frame
4. Each detected face is cropped and resized to 112×112
5. MobileFaceNet produces a 128-d embedding
6. Cosine similarity is computed against every stored student embedding
7. If similarity ≥ **0.75** → student is marked present
8. The student's name appears in a green badge and the chip list
9. When you press **Finish**:
   - Present list is finalised
   - All students NOT seen are marked absent
   - Session is saved to SQLite

---

## Adjusting the recognition threshold

In `lib/services/attendance_service.dart`:
```dart
static const double matchThreshold = 0.75;
```
- **Raise to 0.80** → stricter, fewer false positives (someone else marked present)
- **Lower to 0.70** → more lenient, fewer false negatives (real student not detected)

Start at 0.75 and adjust based on your testing.

---

## Adding new students later

1. Add their photo to `assets/students/`
2. Add the filename to `manifest.txt`
3. In the app → tap the ↻ icon on the Home screen → "Re-enroll"
4. The app reprocesses all images and saves new embeddings

Attendance records are **not** deleted during re-enrollment.

---

## Exporting attendance

- Go to **View Records**
- Select a date
- Tap the download icon (top right)
- Choose to share/save the CSV via Android share sheet

CSV format:
```
Date, Session, Student Name, Status
2024-09-01, 09:15 AM, Alice Johnson, present
2024-09-01, 09:15 AM, Bob Kumar, absent
```

---

## Known limitations & tips

- **One face per frame**: the app matches the largest detected face. If multiple faces appear, it identifies each one but matches the largest. Walk students past the camera one at a time for best results.
- **Glasses / head coverings**: may reduce accuracy slightly. Enroll with the student wearing what they typically wear.
- **Lighting**: ensure the room is well-lit. Very dark environments will cause missed detections.
- **Camera permission**: must be granted the first time. If denied, go to Android Settings → Apps → FaceAttendance → Permissions.
- **Model not bundled**: if you see "model not found" errors, confirm `mobilefacenet.tflite` is in `assets/models/` and listed in `pubspec.yaml`.