from PIL import Image, ImageDraw, ImageFilter

size = 1024
image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
background = Image.new("RGBA", (size, size), (0, 0, 0, 0))
pixels = background.load()
for y in range(52, 972):
    t = (y - 52) / 920
    color = (int(16 - 6 * t), int(28 - 8 * t), int(53 - 14 * t), 255)
    for x in range(52, 972):
        pixels[x, y] = color
mask = Image.new("L", (size, size), 0)
ImageDraw.Draw(mask).rounded_rectangle((52, 52, 972, 972), radius=220, fill=255)
image.alpha_composite(Image.composite(background, Image.new("RGBA", image.size), mask))

draw = ImageDraw.Draw(image)
draw.rounded_rectangle((76, 76, 948, 948), radius=198, outline=(255, 255, 255, 36), width=4)
draw.ellipse((237, 237, 787, 787), fill=(85, 217, 255, 12), outline=(121, 223, 255, 28), width=3)

points = [(184, 530), (309, 530), (366, 400), (457, 652), (548, 331), (633, 530), (840, 530)]
glow = Image.new("RGBA", image.size, (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.line(points, fill=(83, 218, 241, 190), width=54, joint="curve")
glow = glow.filter(ImageFilter.GaussianBlur(18))
image.alpha_composite(glow)

draw = ImageDraw.Draw(image)
colors = [(65, 230, 196, 255), (83, 218, 241, 255), (97, 199, 255, 255),
          (123, 178, 255, 255), (169, 140, 255, 255), (85, 240, 196, 255)]
for index in range(len(points) - 1):
    draw.line([points[index], points[index + 1]], fill=colors[index], width=42)
    draw.ellipse((points[index][0] - 21, points[index][1] - 21,
                  points[index][0] + 21, points[index][1] + 21), fill=colors[index])
draw.ellipse((812, 502, 868, 558), fill=(85, 240, 196, 255))
image.save("Resources/PulseDock.png")
