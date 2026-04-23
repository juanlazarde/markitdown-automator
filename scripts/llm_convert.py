#!/usr/bin/env python3
"""
llm_convert.py — Tier 3 LLM vision conversion for markitdown-automator.

Usage:
    python llm_convert.py --provider [openai|anthropic] INPUT OUTPUT

API key is read from the MARKITDOWN_API_KEY environment variable (never passed
on the command line to avoid transient process-listing exposure).

Handles:
    PDF   — pages rendered via pymupdf at 150 DPI, sent one-by-one to vision API
    Images — JPEG, PNG, WebP sent directly; GIF/TIFF/BMP/HEIC converted to PNG via PIL

Exit codes:
    0 = success
    1 = runtime error (API failure, bad input, etc.)
    2 = missing dependency (pip install needed)
"""

import argparse
import base64
import io
import os
import sys
from pathlib import Path

# ── Python version guard ──────────────────────────────────────────────────────
if sys.version_info < (3, 10):
    print(
        f"ERROR: Python 3.10+ required, found "
        f"{sys.version_info.major}.{sys.version_info.minor}",
        file=sys.stderr,
    )
    sys.exit(2)

# ── Constants ─────────────────────────────────────────────────────────────────

DPI = 150
MAX_PAGES = 50   # cost/time cap for large PDFs

# Formats sent natively (no PIL conversion needed)
NATIVE_FORMATS = {".jpg", ".jpeg", ".png", ".webp"}
# Formats that need PIL conversion to PNG before sending
CONVERT_TO_PNG = {".gif", ".tiff", ".tif", ".bmp", ".heic", ".heif"}
IMAGE_EXTS = NATIVE_FORMATS | CONVERT_TO_PNG

PDF_PROMPT = (
    "Convert this PDF page to clean, well-structured Markdown. "
    "Preserve all headings, lists, tables, and text content accurately. "
    "Represent tables using Markdown table syntax. "
    "If the page is blank or purely decorative, output only: <!-- blank page -->. "
    "Output ONLY the Markdown — no preamble, no explanation."
)

IMAGE_PROMPT = (
    "Describe this image in clean Markdown. "
    "If the image contains text, transcribe it accurately and completely. "
    "If it contains tables or structured data, use Markdown table syntax. "
    "If it contains charts or diagrams, describe them clearly in Markdown. "
    "Output ONLY the Markdown — no preamble, no explanation."
)


# ── PDF rendering ─────────────────────────────────────────────────────────────

def render_pdf_pages(pdf_path: str) -> list[bytes]:
    """Render each PDF page to PNG bytes at DPI resolution via pymupdf."""
    try:
        import fitz  # pymupdf
    except ImportError:
        print(
            "ERROR: pymupdf not installed. Run: bash setup.sh",
            file=sys.stderr,
        )
        sys.exit(2)

    doc = fitz.open(pdf_path)
    pages = []
    matrix = fitz.Matrix(DPI / 72, DPI / 72)

    for i, page in enumerate(doc):
        if i >= MAX_PAGES:
            print(
                f"WARN: PDF has more than {MAX_PAGES} pages — truncating to cap cost",
                file=sys.stderr,
            )
            break
        pixmap = page.get_pixmap(matrix=matrix, colorspace=fitz.csRGB)
        pages.append(pixmap.tobytes("png"))

    doc.close()
    return pages


# ── Image loading ─────────────────────────────────────────────────────────────

def load_image_bytes(image_path: str) -> tuple[bytes, str]:
    """
    Load an image file, returning (bytes, media_type).
    Non-native formats (GIF, TIFF, BMP, HEIC) are converted to PNG via PIL.
    """
    ext = Path(image_path).suffix.lower()

    if ext in CONVERT_TO_PNG:
        try:
            from PIL import Image
        except ImportError:
            print(
                "ERROR: Pillow not installed. Run: bash setup.sh",
                file=sys.stderr,
            )
            sys.exit(2)
        img = Image.open(image_path)
        # GIF: use frame 0; convert mode if needed
        if hasattr(img, "n_frames") and img.n_frames > 1:
            img.seek(0)
        img = img.convert("RGBA") if img.mode in ("P", "LA") else img.convert("RGB")
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        return buf.getvalue(), "image/png"

    # Native format: read raw bytes
    media_type_map = {
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".webp": "image/webp",
    }
    with open(image_path, "rb") as f:
        return f.read(), media_type_map.get(ext, "image/png")


# ── OpenAI conversion ─────────────────────────────────────────────────────────

def convert_openai(api_key: str, image_chunks: list[tuple[bytes, str]], prompt: str) -> str:
    """Send image chunks to OpenAI gpt-4o vision, return concatenated markdown."""
    try:
        from openai import OpenAI
    except ImportError:
        print("ERROR: openai package not installed.", file=sys.stderr)
        sys.exit(2)

    client = OpenAI(api_key=api_key)
    results = []

    for i, (img_bytes, media_type) in enumerate(image_chunks):
        b64 = base64.b64encode(img_bytes).decode()
        data_uri = f"data:{media_type};base64,{b64}"

        response = client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {
                            "type": "image_url",
                            "image_url": {"url": data_uri, "detail": "high"},
                        },
                    ],
                }
            ],
            max_tokens=4096,
        )
        page_md = response.choices[0].message.content or ""
        results.append(page_md.strip())

    return "\n\n---\n\n".join(results)


# ── Anthropic conversion ──────────────────────────────────────────────────────

def convert_anthropic(api_key: str, image_chunks: list[tuple[bytes, str]], prompt: str) -> str:
    """Send image chunks to claude-sonnet-4-6 vision, return concatenated markdown."""
    try:
        import anthropic
    except ImportError:
        print("ERROR: anthropic package not installed.", file=sys.stderr)
        sys.exit(2)

    client = anthropic.Anthropic(api_key=api_key)
    results = []

    for i, (img_bytes, media_type) in enumerate(image_chunks):
        b64 = base64.b64encode(img_bytes).decode()

        message = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=4096,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": media_type,
                                "data": b64,
                            },
                        },
                    ],
                }
            ],
        )
        page_md = message.content[0].text if message.content else ""
        results.append(page_md.strip())

    return "\n\n---\n\n".join(results)


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="LLM vision conversion for markitdown-automator")
    parser.add_argument("--provider", required=True, choices=["openai", "anthropic"])
    parser.add_argument("input_path")
    parser.add_argument("output_path")
    args = parser.parse_args()

    api_key = os.environ.get("MARKITDOWN_API_KEY", "")
    if not api_key:
        print("ERROR: MARKITDOWN_API_KEY environment variable not set", file=sys.stderr)
        sys.exit(1)

    if not os.path.isfile(args.input_path):
        print(f"ERROR: input file not found: {args.input_path}", file=sys.stderr)
        sys.exit(1)

    ext = Path(args.input_path).suffix.lower()

    # Build image chunks and pick prompt
    if ext == ".pdf":
        print(f"Rendering PDF pages at {DPI} DPI...", file=sys.stderr)
        page_bytes = render_pdf_pages(args.input_path)
        if not page_bytes:
            print("ERROR: no pages rendered from PDF", file=sys.stderr)
            sys.exit(1)
        image_chunks = [(b, "image/png") for b in page_bytes]
        prompt = PDF_PROMPT
        print(f"Converting {len(image_chunks)} page(s) via {args.provider}...", file=sys.stderr)

    elif ext in IMAGE_EXTS:
        img_bytes, media_type = load_image_bytes(args.input_path)
        image_chunks = [(img_bytes, media_type)]
        prompt = IMAGE_PROMPT
        print(f"Converting image via {args.provider}...", file=sys.stderr)

    else:
        print(
            f"ERROR: unsupported file type: {ext}\n"
            f"Supported: .pdf, .jpg, .jpeg, .png, .gif, .tiff, .tif, .bmp, .heic, .heif, .webp",
            file=sys.stderr,
        )
        sys.exit(1)

    # Call provider
    try:
        if args.provider == "openai":
            markdown = convert_openai(api_key, image_chunks, prompt)
        else:
            markdown = convert_anthropic(api_key, image_chunks, prompt)
    except Exception as e:
        print(f"ERROR: LLM API call failed: {e}", file=sys.stderr)
        sys.exit(1)

    # Write output atomically (tmp → rename, mirrors convert.sh's safe-write pattern)
    tmp_out = args.output_path + ".llm-tmp"
    try:
        with open(tmp_out, "w", encoding="utf-8") as f:
            f.write(markdown)
        os.replace(tmp_out, args.output_path)
    except OSError as e:
        print(f"ERROR: could not write output: {e}", file=sys.stderr)
        if os.path.exists(tmp_out):
            os.unlink(tmp_out)
        sys.exit(1)


if __name__ == "__main__":
    main()
