# print_server.py
# ---------------------------------------------------------------
# Local HTTP print server — receives visitor data via POST
# and sends it to the Brother QL-810W via bPAC SDK
#
# Run with 32-bit Python (.venv32)
# Usage: python print_server.py
# Listens on: http://localhost:5050
# ---------------------------------------------------------------
import json
import time
import win32com.client
import sys
import io
from datetime import date
from pathlib import Path
from http.server import BaseHTTPRequestHandler, HTTPServer

# Force UTF-8 stdout/stderr — prevents cp1252 crash when logging
# to the NSSM log file. Guard against None (when running as noconsole exe)
if sys.stdout is not None:
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
if sys.stderr is not None:
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

# ── CONFIG ──────────────────────────────────────────────────────
PORT = 5050

# Resolve base directory — works both for .py and compiled .exe
if getattr(sys, "frozen", False):
    # Running as PyInstaller exe — use the folder containing the exe
    BASE_DIR = Path(sys.executable).parent
else:
    # Running as plain .py script
    BASE_DIR = Path(__file__).resolve().parent

TEMPLATE = str(BASE_DIR / "QL-visitor-custom.lbx")
PRINTER = "Brother QL-810W"
# ────────────────────────────────────────────────────────────────


def print_badge(data: dict, retries: int = 3, retry_delay: int = 5) -> tuple[bool, str]:
    name = data.get("visitorName", "").strip()
    company = data.get("visitorCompany", "").strip()
    date_str = data.get("visitorDate", date.today().strftime("%Y/%m/%d")).strip()
    v_type = data.get("visitorType", "Visitor").strip()
    visitor_id = data.get("visitorId", "").strip()
    copies = int(data.get("copies", 1))

    if not name:
        return False, "visitorName is required"

    last_error = ""

    for attempt in range(1, retries + 1):
        try:
            print(f"  Print attempt {attempt}/{retries}...", flush=True)

            doc = win32com.client.Dispatch("bpac.Document")

            if not doc.Open(TEMPLATE):
                return False, f"Could not open template: {TEMPLATE}"

            fields = {
                "visitorName": name,
                "visitorCompany": company,
                "visitorDate": date_str,
                "visitorType": v_type,
            }
            for field_name, value in fields.items():
                try:
                    obj = doc.GetObject(field_name)
                    if obj is not None:
                        obj.Text = value
                except:
                    pass

            if visitor_id:
                barcode_index = doc.GetBarcodeIndex("visitorBarcode")
                doc.SetBarcodeData(barcode_index, visitor_id)

            doc.SetPrinter(PRINTER, True)
            doc.StartPrint("", 0)
            result = doc.PrintOut(copies, 0)
            doc.EndPrint
            doc.Close

            if result:
                return True, f"Printed badge for '{name}'"
            else:
                last_error = "PrintOut returned False — printer may be offline"
                print(f"  Attempt {attempt} failed: {last_error}", flush=True)

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
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        if self.path == "/health":
            self.send_json(
                200, {"status": "ok", "printer": PRINTER, "template": TEMPLATE}
            )
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

        # Safe ASCII log — avoids any encoding issue with unicode names
        safe_log = {
            k: v.encode("ascii", "replace").decode()
            for k, v in data.items()
            if isinstance(v, str)
        }
        print(f"\n  Print job received: {safe_log}", flush=True)

        success, message = print_badge(data)
        print(f"  Result: {'OK' if success else 'FAIL'} — {message}", flush=True)

        if success:
            self.send_json(200, {"success": True, "message": message})
        else:
            self.send_json(500, {"success": False, "message": message})


if __name__ == "__main__":
    server = HTTPServer(("localhost", PORT), PrintHandler)
    print(f"Brother Print Server running on http://localhost:{PORT}", flush=True)
    print(f"  Template : {TEMPLATE}", flush=True)
    print(f"  Printer  : {PRINTER}", flush=True)
    print(f"  Endpoints: GET /health   POST /print", flush=True)
    print(f"\nWaiting for print jobs... (Ctrl+C to stop)\n", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nServer stopped.")
        server.server_close()
