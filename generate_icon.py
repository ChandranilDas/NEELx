import os
import subprocess
from pathlib import Path
import AppKit

base = Path(__file__).resolve().parent

# High-end, premium biometric icon SVG
svg_content = """<?xml version="1.0" encoding="UTF-8"?>
<svg width="1024" height="1024" viewBox="0 0 1024 1024" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <!-- Background Outer Glow & Shadow -->
    <filter id="appShadow" x="40" y="40" width="944" height="964" filterUnits="userSpaceOnUse">
      <feDropShadow dx="0" dy="24" stdDeviation="28" flood-color="#000000" flood-opacity="0.55"/>
      <feDropShadow dx="0" dy="4" stdDeviation="8" flood-color="#00F0FF" flood-opacity="0.15"/>
    </filter>

    <!-- Bevel & Glass Edge -->
    <linearGradient id="bevelGrad" x1="100" y1="100" x2="924" y2="924" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.35"/>
      <stop offset="30%" stop-color="#FFFFFF" stop-opacity="0.08"/>
      <stop offset="70%" stop-color="#00E5FF" stop-opacity="0.05"/>
      <stop offset="100%" stop-color="#000000" stop-opacity="0.4"/>
    </linearGradient>

    <!-- Dark Titanium / Obsidian Background -->
    <linearGradient id="canvasGrad" x1="512" y1="100" x2="512" y2="924" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#141923"/>
      <stop offset="45%" stop-color="#0A0E17"/>
      <stop offset="100%" stop-color="#04060A"/>
    </linearGradient>

    <!-- Radial Iris Depth Glow -->
    <radialGradient id="irisGlow" cx="512" cy="500" r="380" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#00E5FF" stop-opacity="0.22"/>
      <stop offset="35%" stop-color="#0A84FF" stop-opacity="0.12"/>
      <stop offset="70%" stop-color="#5E5CE6" stop-opacity="0.04"/>
      <stop offset="100%" stop-color="#000000" stop-opacity="0"/>
    </radialGradient>

    <!-- Luminous Cyan-to-Azure Biometric Laser Gradient -->
    <linearGradient id="laserGrad" x1="280" y1="280" x2="744" y2="744" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#4EFAFF"/>
      <stop offset="40%" stop-color="#00C8FF"/>
      <stop offset="80%" stop-color="#007AFF"/>
      <stop offset="100%" stop-color="#6B5BFF"/>
    </linearGradient>

    <!-- Platinum Accent Gradient -->
    <linearGradient id="platGrad" x1="400" y1="360" x2="624" y2="680" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#FFFFFF"/>
      <stop offset="50%" stop-color="#D0E8FF"/>
      <stop offset="100%" stop-color="#8BB8E8"/>
    </linearGradient>

    <!-- Glow Filter for Biometric Glyphs -->
    <filter id="neonGlow" x="200" y="200" width="624" height="624" filterUnits="userSpaceOnUse">
      <feGaussianBlur stdDeviation="8" result="blur"/>
      <feMerge>
        <feMergeNode in="blur"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
  </defs>

  <!-- Squircle Base with Realistic macOS Drop Shadow -->
  <g filter="url(#appShadow)">
    <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#canvasGrad)"/>
    <!-- Subtle Glass Edge Highlight -->
    <rect x="100" y="100" width="824" height="824" rx="185" stroke="url(#bevelGrad)" stroke-width="3" fill="none"/>
  </g>

  <!-- Ambient Depth Glow behind Iris -->
  <circle cx="512" cy="512" r="340" fill="url(#irisGlow)"/>

  <!-- Concentric Depth Scanning Rings (Subtle Micro-Pattern) -->
  <circle cx="512" cy="512" r="280" stroke="#00E5FF" stroke-width="1.5" stroke-opacity="0.12" stroke-dasharray="8 12" fill="none"/>
  <circle cx="512" cy="512" r="210" stroke="#0A84FF" stroke-width="1.5" stroke-opacity="0.16" stroke-dasharray="6 8" fill="none"/>
  <circle cx="512" cy="512" r="140" stroke="#00E5FF" stroke-width="1" stroke-opacity="0.1" fill="none"/>

  <!-- Biometric Scanner Corners (Precision Face ID Brackets) -->
  <g filter="url(#neonGlow)">
    <!-- Top-Left Bracket -->
    <path d="M290 410 V340 Q290 290 340 290 H410" stroke="url(#laserGrad)" stroke-width="26" stroke-linecap="round" fill="none"/>
    <!-- Top-Right Bracket -->
    <path d="M614 290 H684 Q734 290 734 340 V410" stroke="url(#laserGrad)" stroke-width="26" stroke-linecap="round" fill="none"/>
    <!-- Bottom-Left Bracket -->
    <path d="M290 614 V684 Q290 734 340 734 H410" stroke="url(#laserGrad)" stroke-width="26" stroke-linecap="round" fill="none"/>
    <!-- Bottom-Right Bracket -->
    <path d="M614 734 H684 Q734 734 734 684 V614" stroke="url(#laserGrad)" stroke-width="26" stroke-linecap="round" fill="none"/>
  </g>

  <!-- Central Facial Biometric Geometry & Integrated 'N' Monogram -->
  <g filter="url(#neonGlow)">
    <!-- Elegant Biometric Eye Points (Focal Nodes) -->
    <circle cx="410" cy="450" r="14" fill="url(#platGrad)"/>
    <circle cx="614" cy="450" r="14" fill="url(#platGrad)"/>
    <circle cx="410" cy="450" r="26" stroke="#00E5FF" stroke-width="3" stroke-opacity="0.45" fill="none"/>
    <circle cx="614" cy="450" r="26" stroke="#00E5FF" stroke-width="3" stroke-opacity="0.45" fill="none"/>

    <!-- Subtle TrueDepth Optical Axis Dots -->
    <circle cx="350" cy="450" r="4" fill="#00E5FF" fill-opacity="0.6"/>
    <circle cx="470" cy="450" r="4" fill="#00E5FF" fill-opacity="0.6"/>
    <circle cx="554" cy="450" r="4" fill="#00E5FF" fill-opacity="0.6"/>
    <circle cx="674" cy="450" r="4" fill="#00E5FF" fill-opacity="0.6"/>

    <!-- Sculpted 'N' + Nose Bridge (Seamless Titanium Centerpiece) -->
    <!-- Left vertical upright -->
    <path d="M460 610 V400" stroke="url(#platGrad)" stroke-width="24" stroke-linecap="round"/>
    <!-- Dynamic diagonal slash connecting left to right -->
    <path d="M460 400 L564 610" stroke="url(#platGrad)" stroke-width="22" stroke-linecap="round"/>
    <!-- Right vertical upright -->
    <path d="M564 610 V400" stroke="url(#platGrad)" stroke-width="24" stroke-linecap="round"/>

    <!-- Harmonious Biometric Smile / Jaw Arc -->
    <path d="M380 655 Q512 755 644 655" stroke="url(#laserGrad)" stroke-width="24" stroke-linecap="round" fill="none"/>
  </g>

  <!-- Top Accent Laser Reflection Line -->
  <path d="M480 290 H544" stroke="#4EFAFF" stroke-width="8" stroke-linecap="round" stroke-opacity="0.8"/>
  <!-- Bottom Laser Tick -->
  <path d="M492 734 H532" stroke="#6B5BFF" stroke-width="8" stroke-linecap="round" stroke-opacity="0.8"/>
</svg>
"""

svg_path = base / 'NEELx_Premium.svg'
svg_path.write_text(svg_content)
print("Saved premium SVG to", svg_path)

# Generate iconset
iconset_dir = base / 'NEELx.iconset'
iconset_dir.mkdir(parents=True, exist_ok=True)

# Rasterize using AppKit NSImage
url = AppKit.NSURL.fileURLWithPath_(str(svg_path))
image = AppKit.NSImage.alloc().initWithContentsOfURL_(url)
if not image:
    raise RuntimeError("Failed to load SVG with NSImage")

sizes = [
    ('icon_16x16.png', 16),
    ('icon_16x16@2x.png', 32),
    ('icon_32x32.png', 32),
    ('icon_32x32@2x.png', 64),
    ('icon_128x128.png', 128),
    ('icon_128x128@2x.png', 256),
    ('icon_256x256.png', 256),
    ('icon_256x256@2x.png', 512),
    ('icon_512x512.png', 512),
    ('icon_512x512@2x.png', 1024),
]

for filename, px in sizes:
    target_size = AppKit.NSSize(px, px)
    bitmap = AppKit.NSBitmapImageRep.alloc().initWithBitmapDataPlanes_pixelsWide_pixelsHigh_bitsPerSample_samplesPerPixel_hasAlpha_isPlanar_colorSpaceName_bytesPerRow_bitsPerPixel_(
        None, px, px, 8, 4, True, False, AppKit.NSCalibratedRGBColorSpace, 0, 0
    )
    AppKit.NSGraphicsContext.saveGraphicsState()
    AppKit.NSGraphicsContext.setCurrentContext_(AppKit.NSGraphicsContext.graphicsContextWithBitmapImageRep_(bitmap))
    image.drawInRect_fromRect_operation_fraction_(
        AppKit.NSMakeRect(0, 0, px, px),
        AppKit.NSZeroRect,
        AppKit.NSCompositeSourceOver,
        1.0
    )
    AppKit.NSGraphicsContext.restoreGraphicsState()
    png_data = bitmap.representationUsingType_properties_(AppKit.NSPNGFileType, {})
    png_path = iconset_dir / filename
    png_data.writeToFile_atomically_(str(png_path), True)

print("Rendered all iconset PNGs.")

# Compile into .icns
icns_path = base / 'GlanceIcon.icns'
subprocess.run(['iconutil', '-c', 'icns', str(iconset_dir), '-o', str(icns_path)], check=True)
print("Compiled .icns successfully at", icns_path)
