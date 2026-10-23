#!/usr/bin/env python3
"""MacCleaner 앱 아이콘 생성 — 1024px macOS squircle 스타일"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, sys

SIZE = 1024
img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# --- macOS squircle 마스크 (rounded rect, Apple 규격 곡률) ---
mask = Image.new("L", (SIZE, SIZE), 0)
md = ImageDraw.Draw(mask)
RADIUS = int(SIZE * 0.2237)  # macOS 아이콘 곡률 (approx)
md.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=RADIUS, fill=255)

# --- 배경 그라데이션 (블루틸): top-left #4FACFE → bottom-right #00C97D ---
grad = Image.new("RGBA", (SIZE, SIZE))
gd = ImageDraw.Draw(grad)
c1 = (79, 172, 254)   # sky blue
c2 = (0, 201, 125)    # emerald
step_h = SIZE
for y in range(step_h):
    t = y / (step_h - 1)
    r = int(c1[0] + (c2[0] - c1[0]) * t)
    g = int(c1[1] + (c2[1] - c1[1]) * t)
    b = int(c1[2] + (c2[2] - c1[2]) * t)
    gd.line([(0, y), (SIZE, y)], fill=(r, g, b, 255))
# 대각선 밝기 강조
highlight = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
hd = ImageDraw.Draw(highlight)
hd.ellipse([-SIZE*0.3, -SIZE*0.5, SIZE*0.9, SIZE*0.45], fill=(255, 255, 255, 60))
highlight = highlight.filter(ImageFilter.GaussianBlur(100))
grad = Image.alpha_composite(grad, highlight)

img.paste(grad, (0, 0), mask)

# --- 중앙 아이콘: 반짝이 별 + 청소 방향 화살표 ---
cx, cy = SIZE // 2, SIZE // 2

# 큰 원형 글래스 원반
glass_r = int(SIZE * 0.30)
d.ellipse([cx - glass_r, cy - glass_r, cx + glass_r, cy + glass_r],
          fill=(255, 255, 255, 42), outline=(255, 255, 255, 150), width=int(SIZE*0.018))

# 반짝이 (4개 스파클)
def sparkle(draw, x, y, r, alpha=255):
    # 다이아 4점 스파클
    pts = [(x, y-r), (x+r, y), (x, y+r), (x-r, y)]
    draw.polygon(pts, fill=(255, 255, 255, alpha))
    thin = Image.new("RGBA", (SIZE, SIZE), (0,0,0,0))
    td = ImageDraw.Draw(thin)
    td.line([(x, y-r*2.2), (x, y+r*2.2)], fill=(255,255,255,alpha//2), width=int(r*0.22))
    td.line([(x-r*2.2, y), (x+r*2.2, y)], fill=(255,255,255,alpha//2), width=int(r*0.22))
    return thin

# 빈 두꺼운 대각선 방향 화살표 (청소 방향) → 우상향 화살표
arrow_color = (255, 255, 255, 255)
lw = int(SIZE * 0.058)
# 대각선 줄기 (좌하→우상)
ax1, ay1 = cx - int(SIZE*0.13), cy + int(SIZE*0.13)
ax2, ay2 = cx + int(SIZE*0.115), cy - int(SIZE*0.115)
d.line([(ax1, ay1), (ax2, ay2)], fill=arrow_color, width=lw)
# 화살촉 (우상향)
head = int(SIZE * 0.075)
for dx in [-1, -1]:
    pass
# 삼각형 화살촉
tip = (ax2, ay2)
perp1 = (ax2 - head, ay2 - int(head*0.1))
perp2 = (ax2 - int(head*0.1), ay2 - head)
d.polygon([tip, perp1, perp2], fill=arrow_color)

# 스파클 배치
layer = sparkle(d, cx - int(SIZE*0.155), cy - int(SIZE*0.155), int(SIZE*0.048))
img = Image.alpha_composite(img, layer)
layer = sparkle(d, cx + int(SIZE*0.19), cy + int(SIZE*0.175), int(SIZE*0.038), alpha=200)
img = Image.alpha_composite(img, layer)
layer = sparkle(d, cx + int(SIZE*0.02), cy + int(SIZE*0.235), int(SIZE*0.026), alpha=160)
img = Image.alpha_composite(img, layer)

# 최종 마스크 적용
out = Image.new("RGBA", (SIZE, SIZE), (0,0,0,0))
out.paste(img, (0,0), mask)
out.save("/Users/parkjunha/Desktop/MacCleaner/AppIcon.png")
print("아이콘 생성 완료:", SIZE, "px")
