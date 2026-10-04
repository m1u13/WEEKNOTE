"""Render the app's W monogram. Run with Python and Pillow."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
assets = root / "WEEKNOTE" / "Assets.xcassets"
directory = assets / "AppIcon.appiconset"
directory.mkdir(parents=True, exist_ok=True)
image = Image.new("RGB", (1024, 1024), "#F8F9F6")
draw = ImageDraw.Draw(image)
font = ImageFont.truetype(str(root / "WEEKNOTE" / "Resources" / "Fonts" / "Anton-Regular.ttf"), 690)
box = draw.textbbox((0, 0), "W", font=font)
draw.text(((1024 - (box[2] - box[0])) / 2 - box[0], (1024 - (box[3] - box[1])) / 2 - box[1] - 15), "W", font=font, fill="#232620")
draw.rounded_rectangle((262, 866, 762, 889), radius=11, fill="#232620")
image.save(directory / "AppIcon.png")
(directory / "Contents.json").write_text(json.dumps({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n", encoding="utf-8")
(assets / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n", encoding="utf-8")
