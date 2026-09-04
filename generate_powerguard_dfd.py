from docx import Document
from docx.enum.table import WD_ALIGN_VERTICAL
from docx.shared import Pt, Inches

def set_cell_border(cell, **kwargs):
    from docx.oxml import OxmlElement
    from docx.oxml.ns import qn
    tc = cell._tc
    tcPr = tc.get_or_add_tcPr()
    tcBorders = tcPr.find(qn('w:tcBorders'))
    if tcBorders is None:
        tcBorders = OxmlElement('w:tcBorders')
        tcPr.append(tcBorders)
    for edge in ('top', 'left', 'bottom', 'right'):
        edge_data = kwargs.get(edge)
        if edge_data:
            tag = 'w:{}'.format(edge)
            element = tcBorders.find(qn(tag))
            if element is None:
                element = OxmlElement(tag)
                tcBorders.append(element)
            for key in ["sz", "val", "color"]:
                if key in edge_data:
                    element.set(qn('w:{}'.format(key)), str(edge_data[key]))

doc = Document()
doc.add_heading('PowerGuard IoT - Context Level Data Flow Diagram (DFD)', 0)

# 9x7 grid to accommodate the layout
table = doc.add_table(rows=9, cols=7)
table.alignment = 1

def make_box(r, c, text, is_process=False):
    cell = table.cell(r, c)
    cell.text = text
    p = cell.paragraphs[0]
    p.alignment = 1
    cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    color = "000000"
    set_cell_border(cell,
                    top={"sz": 12, "val": "single", "color": color},
                    bottom={"sz": 12, "val": "single", "color": color},
                    left={"sz": 12, "val": "single", "color": color},
                    right={"sz": 12, "val": "single", "color": color})
    if p.runs: p.runs[0].bold = True

def make_label(r, c, text, align='center'):
    cell = table.cell(r, c)
    cell.text = text
    p = cell.paragraphs[0]
    p.alignment = 1 if align == 'center' else (0 if align == 'left' else 2)
    cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    if p.runs: p.runs[0].font.size = Pt(8)

# Central Process (The "Management System")
make_box(4, 3, "PowerGuard\nManagement System", is_process=True)

# Entities surrounding it
make_box(1, 1, "Admin User\n(Flutter App)")     # Top Left
make_box(1, 5, "PZEM Meters\n(Hardware)")      # Top Right
make_box(4, 1, "Relay Modules")                # Mid Left
make_box(4, 5, "ESP32 Firmware")               # Mid Right
make_box(7, 1, "Supabase DB\n(Cloud)")         # Bottom Left
make_box(7, 5, "Site Load\n(Protected Devices)")# Bottom Right

# Connecting Labels (Data Flows)
make_label(2, 2, "OFF Commands ↘")
make_label(2, 4, "↙ Metrics Data")
make_label(4, 2, "Trip Signal ←")
make_label(4, 4, "→ GPIO Pulse")
make_label(6, 2, "Sync Logs ↗")
make_label(6, 4, "↖ Status Updates")

doc.add_heading('Data Flow Definitions:', level=2)
doc.add_paragraph('1. OFF Commands: Sent from Admin App via user interaction or schedule.')
doc.add_paragraph('2. Metrics Data: Real-time Voltage, Current, and Power readings from meters.')
doc.add_paragraph('3. Trip Signal: Momentary pulse sent to relay to disconnect the breaker.')
doc.add_paragraph('4. Sync Logs: Persistent storage of all overcurrent and manual trip events.')

path = 'C:/Users/benf/AndroidStudioProjects/PowerGuard_IoT/PowerGuard_System_DFD.docx'
doc.save(path)
print(f"Saved to {path}")
