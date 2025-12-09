import cv2
import dlib
import numpy as np

# 1. Setup the Face Detector and Landmark Predictor
print("[INFO] Loading Face Detector...")
detector = dlib.get_frontal_face_detector()

print("[INFO] Loading Landmark Predictor...")
# Make sure the .dat file is in the same folder as this script!
try:
    predictor = dlib.shape_predictor("shape_predictor_68_face_landmarks.dat")
except RuntimeError:
    print("[ERROR] Could not find 'shape_predictor_68_face_landmarks.dat'!")
    print("Please download and extract it in this folder.")
    exit()

# 2. Open Webcam
cap = cv2.VideoCapture(0)

if not cap.isOpened():
    print("[ERROR] Could not open webcam.")
    exit()

print("[INFO] Starting video stream. Press 'q' to quit.")

while True:
    ret, frame = cap.read()
    if not ret:
        break

    # Convert to grayscale for Dlib
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

    # Detect faces
    faces = detector(gray)

    for face in faces:
        # Draw bounding box
        x1, y1 = face.left(), face.top()
        x2, y2 = face.right(), face.bottom()
        cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)

        # Get landmarks
        landmarks = predictor(gray, face)

        # Draw all 68 points
        for n in range(0, 68):
            x = landmarks.part(n).x
            y = landmarks.part(n).y
            cv2.circle(frame, (x, y), 2, (0, 0, 255), -1)

    cv2.imshow("Face Landmark Check", frame)

    # Press 'q' to exit
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()