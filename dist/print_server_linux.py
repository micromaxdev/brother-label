#!/usr/bin/env python3
# print_server_linux.py
# VMS Print Service — Ubuntu / Linux version
# Replaces bPAC SDK with brother_ql + Pillow
#
# Deps: pip install brother_ql Pillow python-barcode pyusb
# Run:  python3 print_server_linux.py
# Port: http://localhost:5050
# ---------------------------------------------------------------

import io
import json
import time
import sys
from datetime import date
from pathlib import Path
from http.server import BaseHTTPRequestHandler, HTTPServer

try:
    from PIL import Image, ImageDraw, ImageFont
    import qrcode
    from brother_ql.raster import BrotherQLRaster
    from brother_ql.backends.helpers import send
    from brother_ql.conversion import convert
    import usb.core
except ImportError as e:
    print(f"[FAIL] Missing dependency: {e}")
    print("       Run: pip install brother_ql Pillow qrcode[pil] pyusb")
    sys.exit(1)

# ── CONFIG ───────────────────────────────────────────────────────
PORT          = 5050
PRINTER_MODEL = "QL-810W"
LABEL_SIZE    = "62red"       # 62 mm two-colour (black + red) continuous tape
BROTHER_VID   = 0x04f9        # Brother USB vendor ID
BASE_DIR      = Path(__file__).resolve().parent

# Landscape badge — image is wider than tall, rotated 90° when sent to printer.
# LABEL_H = 696 px is fixed (62 mm tape width at 300 DPI).
# LABEL_W = tape length: 1100 px ≈ 93 mm (~3.7") — comfortable badge length.
LABEL_W = 1100
LABEL_H = 696

FONT_PATHS = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
    "/usr/share/fonts/truetype/ubuntu/Ubuntu-B.ttf",
]
FONT_REG_PATHS = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
    "/usr/share/fonts/truetype/ubuntu/Ubuntu-R.ttf",
]
# ─────────────────────────────────────────────────────────────────


def _load_font(paths: list, size: int) -> ImageFont.FreeTypeFont:
    for p in paths:
        if Path(p).exists():
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                continue
    return ImageFont.load_default()


def find_printer_uri() -> str | None:
    dev = usb.core.find(idVendor=BROTHER_VID)
    if dev:
        return f"usb://0x{dev.idVendor:04x}:0x{dev.idProduct:04x}"
    return None


def _wrap_text(text: str, font, max_width: int, draw: ImageDraw.ImageDraw) -> list[str]:
    words = text.split()
    lines, current = [], ""
    for word in words:
        test = (current + " " + word).strip()
        w = draw.textlength(test, font=font)
        if w <= max_width:
            current = test
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines or [""]


def _make_qr(data: str, px_size: int) -> Image.Image:
    """Generate a square QR code image scaled to px_size × px_size."""
    qr = qrcode.QRCode(
        version=None,
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=6,
        border=2,
    )
    qr.add_data(data)
    qr.make(fit=True)
    qr_img = qr.make_image(fill_color="black", back_color="white").convert("RGB")
    return qr_img.resize((px_size, px_size), Image.LANCZOS)


def _load_logo(max_w: int, max_h: int) -> Image.Image | None:
    """Load logo1.png from the same folder as this script, scaled to fit."""
    logo_path = BASE_DIR / "logo1.png"
    if not logo_path.exists():
        print(f"  [WARN] Logo not found at {logo_path}", flush=True)
        return None
    try:
        logo = Image.open(logo_path)
        # Flatten transparency onto white so it prints cleanly
        if logo.mode in ("RGBA", "LA"):
            bg = Image.new("RGB", logo.size, "white")
            bg.paste(logo, mask=logo.split()[-1])
            logo = bg
        else:
            logo = logo.convert("RGB")
        # Scale down to fit within max_w × max_h, preserving aspect ratio
        logo.thumbnail((max_w, max_h), Image.LANCZOS)
        return logo
    except Exception as e:
        print(f"  [WARN] Could not load logo: {e}", flush=True)
        return None


def build_label_image(name: str, company: str,
                      v_type: str, host: str, visitor_id: str) -> Image.Image:
    # ── Canvas ───────────────────────────────────────────────────
    # Landscape orientation — wide × tall (62 mm = 696 px fixed height).
    # rotated 90° in convert() so it prints sideways along the tape.
    img  = Image.new("RGB", (LABEL_W, LABEL_H), "white")
    draw = ImageDraw.Draw(img)

    PAD     = 36          # uniform padding from all edges
    QR_SIZE = 175         # QR code square size in pixels
    BAR_H   = 70          # red bottom bar height

    today = date.today().strftime("%d/%m/%Y")

    # ── QR code — top right ───────────────────────────────────────
    qr_x = LABEL_W - PAD - QR_SIZE
    qr_y = PAD
    if visitor_id:
        try:
            qr_img = _make_qr(visitor_id, QR_SIZE)
            img.paste(qr_img, (qr_x, qr_y))
        except Exception as e:
            print(f"  QR error: {e}", flush=True)

    # ── Logo — top left ───────────────────────────────────────────
    logo_max_w = qr_x - PAD - 30       # stay clear of QR code
    logo_max_h = QR_SIZE               # same height budget as QR
    logo = _load_logo(logo_max_w, logo_max_h)
    if logo:
        # Vertically centre the logo within the QR height zone
        logo_y = PAD + (QR_SIZE - logo.height) // 2
        img.paste(logo, (PAD, logo_y))

    # ── Horizontal divider below logo/QR zone ─────────────────────
    div_y = PAD + QR_SIZE + 18
    draw.line([(PAD, div_y), (LABEL_W - PAD, div_y)], fill="#cccccc", width=2)

    # ── Visitor name ──────────────────────────────────────────────
    content_w = LABEL_W - 2 * PAD
    y = div_y + 22

    f_name = _load_font(FONT_PATHS, 82)
    for line in _wrap_text(name, f_name, content_w, draw):
        draw.text((PAD, y), line, fill="black", font=f_name)
        y += 95

    # ── Company ───────────────────────────────────────────────────
    if company:
        f_co = _load_font(FONT_PATHS, 46)
        for line in _wrap_text(company, f_co, content_w, draw):
            draw.text((PAD, y), line, fill="#333333", font=f_co)
            y += 56

    # ── Red bottom bar — visitor type (left) · host (centre) · date (right) ──
    bar_y = LABEL_H - PAD - BAR_H
    draw.rectangle([(0, bar_y), (LABEL_W, LABEL_H)], fill=(255, 0, 0))

    f_bar  = _load_font(FONT_PATHS,    38)
    f_barr = _load_font(FONT_REG_PATHS, 36)
    text_y = bar_y + (BAR_H - 38) // 2

    # Visitor type — left
    draw.text((PAD, text_y), v_type.upper(), fill="white", font=f_bar)

    # Date — right
    date_w = int(draw.textlength(today, font=f_barr))
    draw.text((LABEL_W - PAD - date_w, text_y + 2), today, fill="white", font=f_barr)

    # Host — centre
    if host:
        host_str = f"Host: {host}"
        host_w   = int(draw.textlength(host_str, font=f_barr))
        draw.text(((LABEL_W - host_w) // 2, text_y + 2), host_str,
                  fill="white", font=f_barr)

    return img


def print_badge(data: dict, retries: int = 3, retry_delay: int = 5) -> tuple[bool, str]:
    name       = data.get("visitorName",    "").strip()
    company    = data.get("visitorCompany", "").strip()
    date_str   = data.get("visitorDate",    date.today().strftime("%Y/%m/%d")).strip()
    v_type     = data.get("visitorType",    "Visitor").strip()
    visitor_id = data.get("visitorId",      "").strip()
    host       = data.get("visitorHost",    "").strip()
    copies     = int(data.get("copies", 1))

    if not name:
        return False, "visitorName is required"

    printer_uri = find_printer_uri()
    if not printer_uri:
        return False, "Brother printer not found. Is the QL-810W connected via USB and powered on?"

    label_image = build_label_image(name, company, v_type, host, visitor_id)
    last_error  = ""

    for attempt in range(1, retries + 1):
        try:
            print(f"  Print attempt {attempt}/{retries} → {printer_uri}", flush=True)

            qlr          = BrotherQLRaster(PRINTER_MODEL)
            instructions = convert(
                qlr=qlr,
                images=[label_image],
                label=LABEL_SIZE,
                rotate="90",
                threshold=70.0,
                dither=False,
                compress=False,
                red=True,
                dpi_600=False,
                hq=True,
                cut=True,
            )
            for _ in range(copies):
                send(
                    instructions=instructions,
                    printer_identifier=printer_uri,
                    backend_identifier="pyusb",
                    blocking=True,
                )

            return True, f"Printed badge for '{name}'"

        except Exception as e:
            last_error = str(e)
            print(f"  Attempt {attempt} failed: {last_error}", flush=True)

        if attempt < retries:
            print(f"  Waiting {retry_delay}s before retry...", flush=True)
            time.sleep(retry_delay)

    return False, f"Failed after {retries} attempts. Last error: {last_error}"


class PrintHandler(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        print(f"  [{self.address_string()}] {format % args}", flush=True)

    def send_json(self, status: int, payload: dict):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type",                "application/json")
        self.send_header("Content-Length",              str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers","Content-Type")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin",  "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        if self.path == "/health":
            printer_uri = find_printer_uri()
            self.send_json(200, {
                "status":  "ok",
                "printer": printer_uri or "not detected",
                "model":   PRINTER_MODEL,
                "label":   LABEL_SIZE,
            })
        else:
            self.send_json(404, {"error": "Not found. POST to /print"})

    def do_POST(self):
        if self.path != "/print":
            self.send_json(404, {"error": "Unknown endpoint"})
            return

        length = int(self.headers.get("Content-Length", 0))
        if length == 0:
            self.send_json(400, {"error": "Empty request body"})
            return

        try:
            body = self.rfile.read(length)
            data = json.loads(body.decode("utf-8"))
        except Exception as e:
            self.send_json(400, {"error": f"Invalid JSON: {e}"})
            return

        safe_log = {k: v.encode("ascii", "replace").decode()
                    for k, v in data.items() if isinstance(v, str)}
        print(f"\n  Print job received: {safe_log}", flush=True)

        success, message = print_badge(data)
        print(f"  Result: {'OK' if success else 'FAIL'} — {message}", flush=True)

        if success:
            self.send_json(200, {"success": True,  "message": message})
        else:
            self.send_json(500, {"success": False, "message": message})


if __name__ == "__main__":
    server = HTTPServer(("localhost", PORT), PrintHandler)
    print(f"Brother Print Server (Linux) running on http://localhost:{PORT}", flush=True)
    print(f"  Model  : {PRINTER_MODEL}", flush=True)
    print(f"  Label  : {LABEL_SIZE} mm continuous tape", flush=True)
    print(f"  Printer: {find_printer_uri() or 'not detected — will retry on each job'}", flush=True)
    print(f"\nWaiting for print jobs... (Ctrl+C to stop)\n", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nServer stopped.")
        server.server_close()
