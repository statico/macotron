"""Write a one-image Word file, since textutil drops images from .docx."""
import sys, zipfile

out, png = sys.argv[1], sys.argv[2]
W, H = 6.0, 6.0 * 480 / 692  # inches, matching charts.png
emu = lambda i: int(i * 914400)

def para(text, size=22, bold=False):
    b = "<w:b/>" if bold else ""
    return f'<w:p><w:r><w:rPr><w:rFonts w:ascii="Helvetica Neue" w:hAnsi="Helvetica Neue"/>{b}<w:sz w:val="{size}"/></w:rPr><w:t xml:space="preserve">{text}</w:t></w:r></w:p>'

pic = f'''<w:p><w:r><w:drawing><wp:inline><wp:extent cx="{emu(W)}" cy="{emu(H)}"/><wp:docPr id="1" name="Charts"/>
<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="1" name="charts.png"/><pic:cNvPicPr/></pic:nvPicPr>
<pic:blipFill><a:blip r:embed="img"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>
<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{emu(W)}" cy="{emu(H)}"/></a:xfrm><a:prstGeom prst="rect"/></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>'''

body = "".join([
    para("Quarterly report", 56, True),
    para("Q3 2027 · Product and growth · Draft for the board", 24),
    para("Revenue grew 18% quarter over quarter to $4.82M, led by Teams seats and the plugin catalog, which doubled to 140 listings."),
    pic,
    para("Highlights", 30, True),
    para("• Active installs reached 128k, up 21% from Q2."),
    para("• Weekly retention held above 60% for the fourth straight quarter."),
    para("• North America remains the largest region; APAC grew fastest at 34%."),
    para("Next quarter", 30, True),
    para("Onboarding, team sharing and a second wave of community plugins."),
])

doc = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"><w:body>{body}</w:body></w:document>'''

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("[Content_Types].xml", '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
    z.writestr("_rels/.rels", '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="doc" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
    z.writestr("word/_rels/document.xml.rels", '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="img" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/charts.png"/></Relationships>')
    z.writestr("word/document.xml", doc)
    z.write(png, "word/media/charts.png")
