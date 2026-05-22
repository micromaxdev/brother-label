# print_visitor.py
# ---------------------------------------------------------------
# Prints a visitor badge on Brother QL-810W via bPAC 3.x SDK
# Run with 32-bit Python (.venv32)
#
# KEY FIX: EndPrint and Close are NOT called with () in this
# version of the COM object — they are property accessors.
# ---------------------------------------------------------------
import win32com.client
import sys
from datetime import date
from pathlib import Path

# ── VISITOR DATA — edit these for each print job ───────────────
VISITOR_NAME = "Mike Barkley"
VISITOR_COMPANY = "Woodward"
VISITOR_DATE = date.today().strftime("%Y/%m/%d")  # e.g. 2026/04/23
VISITOR_TYPE = "Contractor"
COPIES = 1
# ───────────────────────────────────────────────────────────────

# ── TEMPLATE & PRINTER ─────────────────────────────────────────
BASE_DIR = Path(__file__).resolve().parent
TEMPLATE = str(BASE_DIR / "QL-visitor-custom.lbx")
PRINTER = "Brother QL-810W"
# ───────────────────────────────────────────────────────────────

# ── FIELD MAP ──────────────────────────────────────────────────
# To find your exact field names:
#   1. Open QL-visitor.lbx in P-touch Editor
#   2. Click each text object on the label
#   3. Right-click -> Properties (or check the Object Properties panel)
#   4. The "Object Name" field is what goes in the key below
#
# Common Brother SDK visitor template names to try:
FIELD_MAP = {
    "visitorName": VISITOR_NAME,
    "visitorDate": VISITOR_DATE,
    "visitorType": VISITOR_TYPE,
    "visitorCompany": VISITOR_COMPANY,
}
# ───────────────────────────────────────────────────────────────


def try_set_field(doc, name, value):
    """Try to set a field. Returns True if found and set."""
    try:
        obj = doc.GetObject(name)
        if obj is not None:
            obj.Text = value
            return True
        return False
    except Exception as e:
        print(f"  [ERROR] '{name}': {e}")
        return False


def print_badge():
    print("Connecting to bPAC SDK (32-bit COM)...")
    doc = win32com.client.Dispatch("bpac.Document")

    print(f"Opening template: {TEMPLATE}")
    if not doc.Open(TEMPLATE):
        print("ERROR: Failed to open template.")
        sys.exit(1)
    print("Template opened OK.")
    print()

    # ── Inject fields ──────────────────────────────────────────
    for field_name, value in FIELD_MAP.items():
        if try_set_field(doc, field_name, value):
            print(f"  [SET]       '{field_name}' = '{value}'")
        else:
            print(f"  [NOT FOUND] '{field_name}'  <-- check name in P-touch Editor")

    print()

    # ── Set printer ────────────────────────────────────────────
    try:
        doc.SetPrinter(PRINTER, True)
        print(f"Printer set: {PRINTER}")
    except Exception as e:
        print(f"WARNING: SetPrinter failed: {e} — using default printer")

    # ── Print sequence ─────────────────────────────────────────
    # IMPORTANT: StartPrint() uses () but EndPrint and Close do NOT
    # in bPAC 3.x COM — calling them with () causes 'bool not callable'
    print(f"Sending {COPIES} copy/copies...")
    try:
        doc.StartPrint("", 0)
        result = doc.PrintOut(COPIES, 0)

        # Do NOT use () on these — they are COM properties, not methods
        doc.EndPrint
        doc.Close

        if result:
            print("SUCCESS: Print job sent to printer.")
        else:
            print("WARNING: PrintOut returned False.")
            print("  -> Verify printer is on and USB connected")
            print("  -> Make sure Editor Lite LED is OFF on the printer")
            print("  -> In Devices & Printers, confirm 'Brother QL-810W' is online")

    except Exception as e:
        print(f"ERROR during print sequence: {e}")
        try:
            doc.EndPrint
            doc.Close
        except:
            pass
        sys.exit(1)


if __name__ == "__main__":
    print_badge()
