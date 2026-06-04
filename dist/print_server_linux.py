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
    import barcode as bc_lib
    from barcode.writer import ImageWriter
    from brother_ql.raster import BrotherQLRaster
    from brother_ql.backends.helpers import send
    from brother_ql.conversion import convert
    import usb.core
except ImportError as e:
    print(f"[FAIL] Missing dependency: {e}")
    print("       Run: pip install brother_ql Pillow python-barcode pyusb")
    sys.exit(1)

# ── CONFIG ───────────────────────────────────────────────────────
PORT          = 5050
PRINTER_MODEL = "QL-810W"
LABEL_SIZE    = "62red"       # 62 mm two-colour (black + red) continuous tape
BROTHER_VID   = 0x04f9        # Brother USB vendor ID

# 62 mm tape at 300 DPI → 696 px wide (fixed by tape width)
# ~90 mm tall = 1063 px — adjust LABEL_H to resize the badge
LABEL_W = 696
LABEL_H = 1063

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


def build_label_image(name: str, company: str, date_str: str,
                      v_type: str, host: str, visitor_id: str) -> Image.Image:
    img  = Image.new("RGB", (LABEL_W, LABEL_H), "white")
    draw = ImageDraw.Draw(img)

    MARGIN    = 24
    INNER_W   = LABEL_W - 2 * MARGIN
    y         = 0

    # ── Visitor-type banner (red bar — printed in red ink) ───────
    banner_h  = 90
    draw.rectangle([0, y, LABEL_W, y + banner_h], fill=(255, 0, 0))
    f_banner  = _load_font(FONT_PATHS, 56)
    draw.text((MARGIN, y + 16), v_type.upper(), fill="white", font=f_banner)
    y += banner_h + 18

    # ── Visitor name ─────────────────────────────────────────────
    f_name = _load_font(FONT_PATHS, 70)
    for line in _wrap_text(name, f_name, INNER_W, draw):
        draw.text((MARGIN, y), line, fill="black", font=f_name)
        y += 82

    y += 4

    # ── Company ──────────────────────────────────────────────────
    if company:
        f_co = _load_font(FONT_PATHS, 44)
        for line in _wrap_text(company, f_co, INNER_W, draw):
            draw.text((MARGIN, y), line, fill="#222222", font=f_co)
            y += 54

    # ── Host ─────────────────────────────────────────────────────
    if host:
        f_sub = _load_font(FONT_REG_PATHS, 38)
        draw.text((MARGIN, y), f"Host: {host}", fill="#555555", font=f_sub)
        y += 50

    # ── Date ─────────────────────────────────────────────────────
    f_date = _load_font(FONT_REG_PATHS, 38)
    draw.text((MARGIN, y), date_str, fill="#555555", font=f_date)
    y += 50

    # ── Divider line ─────────────────────────────────────────────
    y += 10
    draw.line([MARGIN, y, LABEL_W - MARGIN, y], fill="#cccccc", width=2)
    y += 14

    # ── Barcode ──────────────────────────────────────────────────
    if visitor_id:
        try:
            buf = io.BytesIO()
            code = bc_lib.get("code128", visitor_id, writer=ImageWriter())
            code.write(buf, options={
                "module_height": 14,
                "font_size":     8,
                "text_distance": 4,
                "quiet_zone":    2,
            })
            buf.seek(0)
            bc_img     = Image.open(buf).convert("RGB")
            scale      = INNER_W / bc_img.width
            new_h      = int(bc_img.height * scale)
            bc_img     = bc_img.resize((INNER_W, new_h), Image.LANCZOS)
            remaining  = LABEL_H - y - 10
            if new_h <= remaining:
                img.paste(bc_img, (MARGIN, y))
        except Exception as e:
            print(f"  Barcode error: {e}", flush=True)

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

    label_image = build_label_image(name, company, date_str, v_type, host, visitor_id)
    last_error  = ""

    for attempt in range(1, retries + 1):
        try:
            print(f"  Print attempt {attempt}/{retries} → {printer_uri}", flush=True)

            qlr          = BrotherQLRaster(PRINTER_MODEL)
            instructions = convert(
                qlr=qlr,
                images=[label_image],
                label=LABEL_SIZE,
                rotate="0",
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
