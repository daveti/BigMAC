import argparse
import cairosvg

def convert_svg_to_png(url: str, write_to: str, output_width: int = 8000):
    cairosvg.svg2png(url=url, write_to=write_to, output_width=output_width)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert an SVG file to a PNG image.")
    parser.add_argument("url", help="Path or URL to the input SVG file")
    parser.add_argument("write_to", help="Path to save the output PNG file")
    parser.add_argument("--width", type=int, default=8000, help="Output width of the PNG image (default: 8000)")

    args = parser.parse_args()
    convert_svg_to_png(args.url, args.write_to, args.width)