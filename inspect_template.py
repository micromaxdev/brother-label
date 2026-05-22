# inspect_template.py - final version using doc.Objects collection
import win32com.client
import sys

TEMPLATE = r"C:\Program Files (x86)\Brother bPAC3 SDK\Templates\QL-visitor.lbx"


def inspect_template(path):
    doc = win32com.client.Dispatch("bpac.Document")

    if not doc.Open(path):
        print(f"ERROR: Could not open template: {path}")
        sys.exit(1)

    print(f"Template opened: {path}")
    print(f"Label width: {doc.Width}")
    print()

    # ── Iterate objects via the Objects collection ──────────────
    objs = doc.Objects
    count = objs.Count
    print(f"Object count: {count}")
    print("-" * 60)

    TYPE_MAP = {
        0: "Unknown",
        1: "Text",
        2: "Barcode",
        3: "Image",
        4: "Frame/Box",
        5: "Line",
        6: "Table",
        7: "Time/Date",
    }

    for i in range(count):
        obj = objs[i]
        name = obj.Name if obj.Name else "<unnamed>"
        kind = obj.Type
        text_val = obj.Text if obj.Text else "<empty>"
        type_label = TYPE_MAP.get(kind, f"Type#{kind}")
        print(f"  Index [{i}]  Name: '{name}'  Type: {type_label}  Text: '{text_val}'")

    print()

    # ── Also try SetText index — useful for unnamed objects ─────
    print("Testing SetText by index (for unnamed objects):")
    print("  SetText(0, ...) targets the text object at Z-index 0, etc.")
    print("  Use these indexes in print_visitor.py if objects are unnamed.")

    doc.Close()
    print()
    print("Done.")


if __name__ == "__main__":
    inspect_template(TEMPLATE)
