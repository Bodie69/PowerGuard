from docx import Document
from docx.enum.table import WD_ALIGN_VERTICAL
from docx.shared import Pt, Inches, RGBColor
from docx.oxml import OxmlElement
from docx.oxml.ns import qn

def set_cell_border(cell, **kwargs):
    """
    Set cell border
    Usage: set_cell_border(cell, top={"sz": 12, "val": "single", "color": "#FF0000", "space": "0"}, ...)
    """
    tc = cell._tc
    tcPr = tc.get_or_add_tcPr()

    # check for tag existnace, if none found, then create one
    tcBorders = tcPr.find(qn('w:tcBorders'))
    if tcBorders is None:
        tcBorders = OxmlElement('w:tcBorders')
        tcPr.append(tcBorders)

    for edge in ('top', 'left', 'bottom', 'right', 'insideH', 'insideV'):
        edge_data = kwargs.get(edge)
        if edge_data:
            tag = 'w:{}'.format(edge)
            element = tcBorders.find(qn(tag))
            if element is None:
                element = OxmlElement(tag)
                tcBorders.append(element)

            for key in ["sz", "val", "color", "space"]:
                if key in edge_data:
                    element.set(qn('w:{}'.format(key)), str(edge_data[key]))

doc = Document()
doc.add_heading('PowerGuard IoT - DFD Context Diagram', 0)
doc.add_paragraph('This diagram follows the layout provided in the reference image, mapping the PowerGuard system entities.')

# Create a grid for the diagram
table = doc.add_table(rows=11, cols=7)
table.alignment = 1 # Center

def format_box(r, c, text):
    cell = table.cell(r, c)
    cell.text = text
    p = cell.paragraphs[0]
    p.alignment = 1
    cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    # Add border
    set_cell_border(cell,
                    top={"sz": 12, "val": "single", "color": "000000"},
                    bottom={"sz": 12, "val": "single", "color": "000000"},
                    left={"sz": 12, "val": "single", "color": "000000"},
                    right={"sz": 12, "val": "single", "color": "000000"})
    for run in p.runs:
        run.bold = True

def format_arrow(r, c, text, align='center'):
    cell = table.cell(r, c)
    cell.text = text
    p = cell.paragraphs[0]
    if align == 'center': p.alignment = 1
    elif align == 'left': p.alignment = 0
    elif align == 'right': p.alignment = 2
    cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    for run in p.runs:
        run.font.size = Pt(8)

# Central System
format_box(5, 3, 'PowerGuard\nManagement System')

# Top Left: User
format_box(1, 1, 'User (Admin)')
format_arrow(2, 1, '|')
format_arrow(3, 1, 'v\npayments (OFF command)')
format_arrow(3, 2, '------>')

# Top Right: Vendors -> PZEM
format_box(1, 5, 'PZEM Energy Meters')
format_arrow(2, 5, '|')
format_arrow(3, 5, 'v\nsupplies (metrics)')
format_arrow(3, 4, '<------')

# Bottom Left: Manager -> Relay
format_box(9, 1, 'Relay Modules')
format_arrow(8, 1, '^')
format_arrow(7, 1, '|\ntrip signal')
format_arrow(7, 2, '------>')

# Bottom Right: Chief Warden -> Database
format_box(9, 5, 'Supabase Database')
format_arrow(8, 5, '^')
format_arrow(7, 5, '|\nlogs/history')
format_arrow(7, 4, '<------')

# Flow Labels mimicking the image
format_arrow(4, 3, '^ extra notes (Schedules)')
format_arrow(4, 4, ' | ')

format_arrow(6, 3, 'v status alerts')
format_arrow(6, 4, ' | ')

output_path = 'C:/Users/benf/AndroidStudioProjects/PowerGuard_IoT/PowerGuard_Context_DFD.docx'
doc.save(output_path)
print(f'Saved to {output_path}')
