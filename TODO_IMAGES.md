# TODO: Create Images

The add-on needs two image files before publishing:

## Required Images

1. **icon.png** - 108x108 pixels
2. **logo.png** - 128x128 pixels

## Design Suggestions

### Colors
- Home Assistant Blue: #41BDF5 (rgb(65, 189, 245))
- White: #FFFFFF
- Dark Gray: #333333

### Concept
- Robot or AI agent symbol
- Simple, clean design
- Works well at small sizes
- Transparent background or HA blue background

## Quick Creation Options

### Option 1: Using DALL-E or AI Image Generator
```
Prompt: "Simple robot icon on blue background, 108x108 pixels, minimalist design for Home Assistant add-on, clean and modern"
```

### Option 2: Using Figma/Canva
1. Create 108x108 canvas
2. Use HA blue background (#41BDF5)
3. Draw simple robot symbol in white
4. Export as PNG
5. Duplicate and resize to 128x128 for logo

### Option 3: Using Python + Pillow (once installed)
```bash
pip3 install pillow
python3 << 'EOF'
from PIL import Image, ImageDraw

# Create icon
icon = Image.new('RGBA', (108, 108), (65, 189, 245, 255))
draw = ImageDraw.Draw(icon)
draw.rectangle([30, 25, 78, 55], fill=(255, 255, 255, 255))
draw.rectangle([25, 60, 83, 90], fill=(255, 255, 255, 255))
draw.ellipse([38, 35, 48, 45], fill=(65, 189, 245, 255))
draw.ellipse([60, 35, 70, 45], fill=(65, 189, 245, 255))
icon.save('icon.png', 'PNG')

# Create logo
logo = Image.new('RGBA', (128, 128), (65, 189, 245, 255))
draw = ImageDraw.Draw(logo)
draw.rectangle([35, 30, 93, 65], fill=(255, 255, 255, 255))
draw.rectangle([30, 70, 98, 105], fill=(255, 255, 255, 255))
draw.ellipse([45, 42, 58, 55], fill=(65, 189, 245, 255))
draw.ellipse([70, 42, 83, 55], fill=(65, 189, 245, 255))
logo.save('logo.png', 'PNG')
EOF
```

## For Now

The add-on will work without images in development/testing, but they are required before publishing to the Home Assistant add-on store.

**Action**: Create these images before final release.
