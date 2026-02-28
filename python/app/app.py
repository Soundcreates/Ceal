import base64
import hashlib
import os
from typing import Any

import cv2
import numpy as np
import requests
from fastapi import FastAPI, File, Form, HTTPException, UploadFile


TS_BACKEND_URL = os.getenv(
    "TS_BACKEND_URL",
    "http://backend:3000/v1/onboarding/ingest-aadhaar-photo",
)
PYTHON_SERVICE_SECRET = os.getenv("PYTHON_SERVICE_SECRET", "")
REQUEST_TIMEOUT_SEC = float(os.getenv("PYTHON_REQUEST_TIMEOUT_SEC", "20"))

app = FastAPI(title="AfterMath Python QR Service", version="1.0.0")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/v1/qr/scan-aadhaar-photo")
async def scan_aadhaar_photo(
    user_id: str = Form(...),
    image: UploadFile = File(...),
) -> dict[str, Any]:
    content = await image.read()
    if len(content) == 0:
        raise HTTPException(status_code=400, detail="Uploaded image is empty")

    decoded_xml = decode_qr_from_image(content)
    if "PrintLetterBarcodeData" not in decoded_xml:
        raise HTTPException(
            status_code=422,
            detail="QR decoded but payload is not Aadhaar XML",
        )

    sha256 = hashlib.sha256(content).hexdigest()
    image_b64 = base64.b64encode(content).decode("ascii")

    payload = {
        "userId": user_id,
        "rawXml": decoded_xml,
        "imageBase64": image_b64,
        "imageSha256": sha256,
        "source": "photo",
        "processedBy": "python-fastapi-opencv",
    }
    headers = {"Content-Type": "application/json"}
    if PYTHON_SERVICE_SECRET:
        headers["x-python-service-secret"] = PYTHON_SERVICE_SECRET

    try:
        resp = requests.post(
            TS_BACKEND_URL,
            json=payload,
            headers=headers,
            timeout=REQUEST_TIMEOUT_SEC,
        )
    except requests.RequestException as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Failed to forward to TS backend: {exc}",
        ) from exc

    body: Any
    try:
        body = resp.json()
    except Exception:
        body = {"raw": resp.text}

    if resp.status_code >= 400:
        raise HTTPException(
            status_code=resp.status_code,
            detail={"forwardError": body},
        )

    return {
        "ok": True,
        "decodedXml": decoded_xml,
        "imageSha256": sha256,
        "forwardedToTs": True,
        "tsResponse": body,
    }


def decode_qr_from_image(content: bytes) -> str:
    arr = np.frombuffer(content, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise HTTPException(status_code=400, detail="Invalid image format")

    detector = cv2.QRCodeDetector()

    for candidate in _iter_qr_candidates(img):
        decoded = _decode_qr(detector, candidate)
        if decoded:
            return decoded

    raise HTTPException(status_code=422, detail="No QR code detected in image")


def _decode_qr(detector: cv2.QRCodeDetector, img: np.ndarray) -> str | None:
    try:
        ok_multi, decoded_multi, _, _ = detector.detectAndDecodeMulti(img)
        if ok_multi and decoded_multi:
            for decoded in decoded_multi:
                if decoded and decoded.strip():
                    return decoded.strip()
    except cv2.error:
        # Some transformed candidates can fail internally; skip them.
        pass

    try:
        decoded_single, _, _ = detector.detectAndDecode(img)
        if decoded_single and decoded_single.strip():
            return decoded_single.strip()
    except cv2.error:
        pass

    return None


def _iter_qr_candidates(img: np.ndarray):
    # Original frame first.
    yield img

    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    yield gray

    # Improve sharpness and contrast for glossy/low-light captures.
    blur = cv2.GaussianBlur(gray, (3, 3), 0)
    yield blur

    adaptive = cv2.adaptiveThreshold(
        blur,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        31,
        5,
    )
    yield adaptive

    _, otsu = cv2.threshold(blur, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    yield otsu

    # Upscale candidates because phone captures often contain small QR regions.
    for fx in (1.5, 2.0, 3.0):
        up = cv2.resize(gray, None, fx=fx, fy=fx, interpolation=cv2.INTER_CUBIC)
        yield up

    # Rotation fallback for off-angle captures.
    for code in (
        cv2.ROTATE_90_CLOCKWISE,
        cv2.ROTATE_180,
        cv2.ROTATE_90_COUNTERCLOCKWISE,
    ):
        rotated = cv2.rotate(gray, code)
        yield rotated
