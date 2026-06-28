import onnxruntime as ort
import numpy as np

sess = ort.InferenceSession("e:/project/gift_fras/assets/models/best_model.onnx")

from PIL import Image
import numpy as np

#img = Image.open("e:/project/gift_fras/assets/models/test_face.jpg").resize((80, 80))
img = Image.open("e:/project/gift_fras/assets/models/test_face.jpg").resize((128, 128))
arr = np.array(img).astype(np.float32) / 255.0
arr = arr.transpose(2, 0, 1)[np.newaxis]  # NCHW
out = sess.run(None, {sess.get_inputs()[0].name: arr})
print("Real face →", out[0])

# Check input/output
for i in sess.get_inputs():
    print("Input:", i.name, i.shape, i.type)
for o in sess.get_outputs():
    print("Output:", o.name, o.shape, o.type)

# Test with a white image (real-ish) and black image (spoof-ish)
for val in [0.0, 0.5, 1.0]:
    #dummy = np.full((1, 3, 80, 80), val, dtype=np.float32)
    dummy = np.full((1, 3, 128, 128), val, dtype=np.float32)
    out = sess.run(None, {sess.get_inputs()[0].name: dummy})
    print(f"pixel={val} → {out[0]}")

# Try BGR order
arr_bgr = arr[:, ::-1, :, :]  # flip channels
out = sess.run(None, {sess.get_inputs()[0].name: arr_bgr})
print("BGR →", out[0])

# Try (pixel - 127.5) / 128
arr_norm = (arr * 255 - 127.5) / 128.0
out = sess.run(None, {sess.get_inputs()[0].name: arr_norm})
print("ArcFace norm →", out[0])