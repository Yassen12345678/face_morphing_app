import cv2
import numpy as np
import dlib
import glob

# --- CONFIGURATION ---
PREDICTOR_PATH = 'shape_predictor_68_face_landmarks.dat'
# ---------------------

# ==========================================
# HELPER: ARABIC FILE LOADER
# ==========================================
def imread_unicode(path):
    try:
        with open(path, "rb") as f:
            bytes_data = bytearray(f.read())
            numpy_array = np.asarray(bytes_data, dtype=np.uint8)
            return cv2.imdecode(numpy_array, cv2.IMREAD_COLOR)
    except Exception:
        return None

# ==========================================
# HELPER: COLOR TRANSFER
# ==========================================
def apply_color_transfer(source, target):
    """
    Matches the color distribution of the source image to the target (webcam) image.
    This helps the pasted face blend in with your actual skin tone/lighting.
    """
    # Convert to LAB color space (separates Lightness from Color)
    s_lab = cv2.cvtColor(source, cv2.COLOR_BGR2LAB).astype("float32")
    t_lab = cv2.cvtColor(target, cv2.COLOR_BGR2LAB).astype("float32")

    # Compute statistics
    (lMeanSrc, lStdSrc) = (s_lab[...,0].mean(), s_lab[...,0].std())
    (aMeanSrc, aStdSrc) = (s_lab[...,1].mean(), s_lab[...,1].std())
    (bMeanSrc, bStdSrc) = (s_lab[...,2].mean(), s_lab[...,2].std())

    (lMeanTar, lStdTar) = (t_lab[...,0].mean(), t_lab[...,0].std())
    (aMeanTar, aStdTar) = (t_lab[...,1].mean(), t_lab[...,1].std())
    (bMeanTar, bStdTar) = (t_lab[...,2].mean(), t_lab[...,2].std())

    # Subtract the means from the source
    (l, a, b) = cv2.split(s_lab)
    l -= lMeanSrc
    a -= aMeanSrc
    b -= bMeanSrc

    # Scale by the standard deviations
    l = (lStdTar / lStdSrc) * l
    a = (aStdTar / aStdSrc) * a
    b = (bStdTar / bStdSrc) * b

    # Add the target means
    l += lMeanTar
    a += aMeanTar
    b += bMeanTar

    # Clip and convert back
    l = np.clip(l, 0, 255)
    a = np.clip(a, 0, 255)
    b = np.clip(b, 0, 255)

    transfer = cv2.merge([l, a, b])
    transfer = cv2.cvtColor(transfer.astype("uint8"), cv2.COLOR_LAB2BGR)
    return transfer

# ==========================================
# HELPER: ADD FOREHEAD POINTS
# ==========================================
# ==========================================
# HELPER: STABLE FOREHEAD POINTS
# ==========================================
def add_forehead_points(points):
    """
    Calculates forehead points based on the distance between eyes (stable)
    instead of eyebrows (which move), preventing the 'stretching' effect.
    """
    p = np.array(points)

    # Get the center of the eyes (Points 36-41 are Left Eye, 42-47 are Right Eye)
    left_eye_center = np.mean(p[36:42], axis=0)
    right_eye_center = np.mean(p[42:48], axis=0)

    # Calculate the mid-point between eyes
    eye_midpoint = (left_eye_center + right_eye_center) / 2

    # Calculate the distance between eyes (Interocular distance)
    # This is a constant 'ruler' for the face size that never changes with expression
    eye_distance = np.linalg.norm(left_eye_center - right_eye_center)

    # Calculate the angle of the face (to handle head tilting)
    dy = right_eye_center[1] - left_eye_center[1]
    dx = right_eye_center[0] - left_eye_center[0]
    angle = np.arctan2(dy, dx)

    # We want to go "UP" perpendicular to the eye line
    # -90 degrees (or -pi/2 radians) from the eye angle is "Up"
    up_angle = angle - (np.pi / 2)

    # Calculate the forehead height vector
    # Usually, the hairline is about 1.2 to 1.5 times the eye-distance above the eyes
    forehead_height = eye_distance * 1.1

    # Calculate the specific offset vector using sin/cos
    offset_x = np.cos(up_angle) * forehead_height
    offset_y = np.sin(up_angle) * forehead_height

    # The new forehead center point
    forehead_center = (eye_midpoint[0] + offset_x, eye_midpoint[1] + offset_y)

    # Create left and right forehead points slightly wider than the eyes
    # We simply shift the center point left/right along the original eye angle
    side_spread = eye_distance * 0.8

    left_x = forehead_center[0] - np.cos(angle) * side_spread
    left_y = forehead_center[1] - np.sin(angle) * side_spread

    right_x = forehead_center[0] + np.cos(angle) * side_spread
    right_y = forehead_center[1] + np.sin(angle) * side_spread

    forehead_left = (left_x, left_y)
    forehead_right = (right_x, right_y)

    # Append to points list
    new_points = points.copy()
    new_points.append((int(forehead_left[0]), int(forehead_left[1])))
    new_points.append((int(forehead_center[0]), int(forehead_center[1])))
    new_points.append((int(forehead_right[0]), int(forehead_right[1])))

    return new_points

# ==========================================
# MAIN LOGIC
# ==========================================

# 1. MENU SYSTEM
raw_files = []
for file_type in ['*.jpg', '*.jpeg', '*.png', '*.JPG', '*.PNG']:
    raw_files.extend(glob.glob(file_type))
image_files = sorted(list(set(raw_files)))

if not image_files:
    print("Error: No images found.")
    exit()

print("\n--- AVAILABLE FACES ---")
for i, filename in enumerate(image_files):
    print(f"[{i}] {filename}")
print("-----------------------")

try:
    selection = input("Select face (number): ")
    STATIC_IMAGE_PATH = image_files[int(selection)]
except:
    print("Invalid selection.")
    exit()

detector = dlib.get_frontal_face_detector()
predictor = dlib.shape_predictor(PREDICTOR_PATH)

# 2. LOAD & PROCESS STATIC IMAGE
img_source_orig = imread_unicode(STATIC_IMAGE_PATH)
if img_source_orig is None:
    exit()

# Detect landmarks
img_gray_source = cv2.cvtColor(img_source_orig, cv2.COLOR_BGR2GRAY)
rects = detector(img_gray_source)
if len(rects) == 0:
    print("No face detected in source.")
    exit()

landmarks = predictor(img_gray_source, rects[0])
points_source_raw = []
for n in range(0, 68):
    points_source_raw.append((landmarks.part(n).x, landmarks.part(n).y))

# --- UPGRADE: EXTEND POINTS TO FOREHEAD ---
points_source = add_forehead_points(points_source_raw)

# Triangulate Source
rect = (0, 0, img_source_orig.shape[1], img_source_orig.shape[0])
subdiv = cv2.Subdiv2D(rect)
for p in points_source:
    if p[0] < 0 or p[0] >= img_source_orig.shape[1] or p[1] < 0 or p[1] >= img_source_orig.shape[0]:
        continue # Skip points outside image
    subdiv.insert(p)

triangle_list = subdiv.getTriangleList()
triangles_indices = []

for t in triangle_list:
    pt1 = (t[0], t[1])
    pt2 = (t[2], t[3])
    pt3 = (t[4], t[5])

    # Helper to find index
    def get_index(pt, points_list):
        pt_np = np.array(pt)
        # Allow small margin of error for float/int conversion
        dist = np.linalg.norm(np.array(points_list) - pt_np, axis=1)
        min_dist_idx = np.argmin(dist)
        if dist[min_dist_idx] < 1.0: # Close enough
            return min_dist_idx
        return None

    i1 = get_index(pt1, points_source)
    i2 = get_index(pt2, points_source)
    i3 = get_index(pt3, points_source)

    if i1 is not None and i2 is not None and i3 is not None:
        triangles_indices.append([i1, i2, i3])

print(f"Generated {len(triangles_indices)} triangles (including forehead).")
print("Starting Camera... (Press ESC to exit)")

cap = cv2.VideoCapture(0)

while True:
    ret, frame = cap.read()
    if not ret: break

    img_target = frame
    height, width, _ = img_target.shape

    # 3. COLOR CORRECTION (Run every frame to match lighting)
    # Note: For speed, we could do this once, but lighting changes.
    # We warp the source face color to match the webcam frame color
    img_source_colored = apply_color_transfer(img_source_orig, img_target)

    target_rects = detector(cv2.cvtColor(img_target, cv2.COLOR_BGR2GRAY))

    if len(target_rects) > 0:
        landmarks_t = predictor(cv2.cvtColor(img_target, cv2.COLOR_BGR2GRAY), target_rects[0])
        points_target_raw = []
        for n in range(0, 68):
            points_target_raw.append((landmarks_t.part(n).x, landmarks_t.part(n).y))

        # --- UPGRADE: EXTEND TARGET POINTS TOO ---
        points_target = add_forehead_points(points_target_raw)

        # Create a black canvas for the face only
        img_new_face = np.zeros_like(img_target)

        # WARPING LOOP
        for triangle_index in triangles_indices:
            # Source Triangle
            tr1_pt1 = points_source[triangle_index[0]]
            tr1_pt2 = points_source[triangle_index[1]]
            tr1_pt3 = points_source[triangle_index[2]]

            rect1 = cv2.boundingRect(np.array([tr1_pt1, tr1_pt2, tr1_pt3], np.int32))
            (x1, y1, w1, h1) = rect1
            # Crop from the COLOR CORRECTED source
            cropped_triangle1 = img_source_colored[y1:y1+h1, x1:x1+w1]

            points1 = np.array([[tr1_pt1[0]-x1, tr1_pt1[1]-y1],
                                [tr1_pt2[0]-x1, tr1_pt2[1]-y1],
                                [tr1_pt3[0]-x1, tr1_pt3[1]-y1]], np.int32)

            # Target Triangle
            tr2_pt1 = points_target[triangle_index[0]]
            tr2_pt2 = points_target[triangle_index[1]]
            tr2_pt3 = points_target[triangle_index[2]]

            rect2 = cv2.boundingRect(np.array([tr2_pt1, tr2_pt2, tr2_pt3], np.int32))
            (x2, y2, w2, h2) = rect2

            if x2 < 0 or y2 < 0 or (x2+w2) > width or (y2+h2) > height:
                continue

            cropped_triangle2 = np.zeros((h2, w2, 3), np.uint8)
            points2 = np.array([[tr2_pt1[0]-x2, tr2_pt1[1]-y2],
                                [tr2_pt2[0]-x2, tr2_pt2[1]-y2],
                                [tr2_pt3[0]-x2, tr2_pt3[1]-y2]], np.int32)

            # Warp
            warp_mat = cv2.getAffineTransform(np.float32(points1), np.float32(points2))
            cropped_triangle2 = cv2.warpAffine(cropped_triangle1, warp_mat, (w2, h2), None,
                                               flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT_101)

            # Masking
            mask = np.zeros((h2, w2), dtype=np.uint8)
            cv2.fillConvexPoly(mask, np.int32(points2), 255)

            # --- SEAM FIX ---
            # Instead of adding directly, we erase the area in the canvas and put the new piece in
            # This prevents the "White Line" overlap accumulation

            # 1. Invert mask to cut a hole in the current new_face canvas
            mask_inv = cv2.bitwise_not(mask)
            roi = img_new_face[y2:y2+h2, x2:x2+w2]

            # Black out the area of the triangle in ROI
            img_bg = cv2.bitwise_and(roi, roi, mask=mask_inv)

            # Take only the triangle region from warped image
            img_fg = cv2.bitwise_and(cropped_triangle2, cropped_triangle2, mask=mask)

            # Put them back together
            dst = cv2.add(img_bg, img_fg)
            img_new_face[y2:y2+h2, x2:x2+w2] = dst


        # Final Blending
        img_new_face_gray = cv2.cvtColor(img_new_face, cv2.COLOR_BGR2GRAY)
        _, final_head_mask = cv2.threshold(img_new_face_gray, 1, 255, cv2.THRESH_BINARY)

        final_head_mask_inv = cv2.bitwise_not(final_head_mask)
        img_bg = cv2.bitwise_and(img_target, img_target, mask=final_head_mask_inv)

        result = cv2.add(img_bg, img_new_face)

        # (Optional) Uncomment this for PERFECT blending, but it will be slow (5-10 FPS)
        # center_face = (int(cv2.boundingRect(np.array(points_target))[0] + cv2.boundingRect(np.array(points_target))[2]/2),
        #                int(cv2.boundingRect(np.array(points_target))[1] + cv2.boundingRect(np.array(points_target))[3]/2))
        # result = cv2.seamlessClone(img_new_face, img_target, final_head_mask, center_face, cv2.NORMAL_CLONE)

        cv2.imshow("Advanced Face Swap", result)
    else:
        cv2.imshow("Advanced Face Swap", frame)

    if cv2.waitKey(1) == 27:
        break

cap.release()
cv2.destroyAllWindows()