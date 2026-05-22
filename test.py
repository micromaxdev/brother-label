# run once to confirm barcode index
import win32com.client

TEMPLATE = r"C:\Users\Saziz\Documents\GitHub\brother-label\QL-visitor-custom.lbx"
doc = win32com.client.Dispatch("bpac.Document")
doc.Open(TEMPLATE)
idx = doc.GetBarcodeIndex("visitorBarcode")
print(f"Barcode index: {idx}")
doc.Close
