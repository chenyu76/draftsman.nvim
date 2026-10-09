#!/usr/bin/env python3
"""
Capture actual Draftsman key input and render GIFs in README.

Requires Python 3 with Pillow and Neovim on PATH.
    $ python render.py [--config path] [--only name]

Current Font:
    https://github.com/subframe7536/maple-font
Current Palette:
    https://github.com/catppuccin/catppuccin
"""

import argparse
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]


def dimensions(frames, cfg, cell_width):
    columns = rows = 0
    for frame in frames:
        row, col = frame["cursor"]
        rows, columns = max(rows, row), max(columns, col + 1)
        for index, line in enumerate(frame["lines"]):
            if line.rstrip():
                rows = max(rows, index + 1)
                columns = max(columns, len(line.rstrip()))
    columns = max(cfg["min_columns"], columns + cfg["extra_columns"])
    rows = max(cfg["min_rows"], rows + cfg["extra_rows"])
    gutter = (len(str(rows)) + 2) * cell_width if cfg["line_numbers"] else 0
    width = 2 * cfg["padding_x"] + gutter + columns * cell_width
    height = (
        2 * cfg["padding_y"] + rows * cfg["line_height"] + cfg["keybar_height"]
    )
    return width, height, rows, gutter


def render_frame(frame, cfg, font, size, cell_width, history):
    width, height, rows, gutter = size
    colors = cfg["colors"]
    img = Image.new("RGB", (width, height), colors["background"])
    draw = ImageDraw.Draw(img)
    origin_x = cfg["padding_x"] + gutter
    origin_y = cfg["padding_y"]
    line_height = cfg["line_height"]
    # Center glyphs by the font's ascent/descent; box drawing glyphs meet cell edges.
    ascent, descent = font.getmetrics()
    baseline_offset = (line_height - ascent - descent) // 2 + ascent

    def cell(row, col, char, color):
        x = origin_x + col * cell_width
        y = origin_y + (row - 1) * line_height
        draw.text(
            (x, y + baseline_offset), char, font=font, fill=color, anchor="ls"
        )

    cursor_row, cursor_col = frame["cursor"]
    if cfg["cursorline"]:
        y = origin_y + (cursor_row - 1) * line_height
        draw.rectangle(
            (
                cfg["padding_x"],
                y,
                width - cfg["padding_x"] - 1,
                y + line_height - 1,
            ),
            fill=colors["cursorline"],
        )
    for row in range(1, rows + 1):
        if cfg["line_numbers"]:
            number = (
                abs(row - cursor_row)
                if cfg["relative_numbers"] and row != cursor_row
                else row
            )
            draw.text(
                (
                    origin_x - cell_width,
                    origin_y + (row - 1) * line_height + baseline_offset,
                ),
                str(number),
                font=font,
                fill=(
                    colors["foreground"]
                    if row == cursor_row
                    else colors["gutter"]
                ),
                anchor="rs",
            )
        line = frame["lines"][row - 1] if row <= len(frame["lines"]) else ""
        for col, char in enumerate(line):
            if char != " ":
                cell(row, col, char, colors["foreground"])

    overlay = {}
    if frame["anchor"] is not None:
        anchor_row, anchor_col = frame["anchor"]
        top, bottom = sorted((anchor_row, cursor_row))
        left, right = sorted((anchor_col, cursor_col))
        for row in range(top, bottom + 1):
            for col in range(left, right + 1):
                if row in (top, bottom) or col in (left, right):
                    overlay[(row, col)] = (
                        "+"
                        if row in (top, bottom) and col in (left, right)
                        else "-" if row in (top, bottom) else "|"
                    )
        if top == bottom and left == right:
            overlay[(top, left)] = "⊕"
        for (row, col), char in overlay.items():
            x, y = (
                origin_x + col * cell_width,
                origin_y + (row - 1) * line_height,
            )
            draw.rectangle(
                (x, y, x + cell_width - 1, y + line_height - 1),
                fill=colors["marker_background"],
            )
            cell(row, col, char, colors["marker"])

    x, y = (
        origin_x + cursor_col * cell_width,
        origin_y + (cursor_row - 1) * line_height,
    )
    draw.rectangle(
        (x, y, x + cell_width - 1, y + line_height - 1), fill=colors["cursor"]
    )
    line = frame["lines"][cursor_row - 1]
    char = overlay.get(
        (cursor_row, cursor_col),
        line[cursor_col] if cursor_col < len(line) else " ",
    )
    cell(cursor_row, cursor_col, char, colors["cursor_text"])

    if cfg["keybar_height"]:
        top = height - cfg["keybar_height"]
        draw.rectangle((0, top, width, height), fill=colors["keybar"])
        # Always show the actual key; repeated presses are grouped in the history.
        groups = []
        for key in history:
            if groups and groups[-1][0] == key:
                groups[-1][1] += 1
            else:
                groups.append([key, 1])
        labels = [
            (key if count == 1 else f"{key} ×{count}")
            for key, count in groups[-cfg["key_history_length"] :]
        ]
        while (
            len(labels) > 1
            and font.getlength("   ".join(labels))
            > width - cfg["padding_x"] * 2
        ):
            labels.pop(0)
        x = cfg["padding_x"]
        y = top + (cfg["keybar_height"] - ascent - descent) // 2 + ascent
        for index, label in enumerate(labels):
            draw.text(
                (x, y),
                label,
                font=font,
                fill=(
                    colors["key"]
                    if index == len(labels) - 1
                    else colors["key_history"]
                ),
                anchor="ls",
            )
            x += font.getlength(label + "   ")
    return img


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--config", type=Path, default=Path(__file__).with_name("config.json")
    )
    parser.add_argument(
        "--only",
        choices=[
            "stroke",
            "arrow",
            "rectangle",
            "text",
            "move",
            "eraser",
            "clipboard",
            "styles",
        ],
    )
    parser.add_argument(
        "--output", type=Path, help="Override the output directory"
    )
    parser.add_argument(
        "--frames-dir",
        type=Path,
        help="Optionally save raw captured frames for inspection",
    )
    parser.add_argument("--nvim", default="nvim")
    args = parser.parse_args()
    cfg = json.loads(args.config.read_text())
    if args.only:
        cfg["scenarios"] = [
            s for s in cfg["scenarios"] if s["name"] == args.only
        ]
    if not cfg["scenarios"]:
        parser.error("No matching scenarios in config")
    font = ImageFont.truetype(cfg["font_path"], cfg["font_size"])
    cell_width = cfg["cell_width"] or math.ceil(font.getlength("M"))
    output = args.output or ROOT / cfg["output_dir"]
    output.mkdir(parents=True, exist_ok=True)
    nvim = shutil.which(args.nvim)
    if not nvim:
        parser.error("Neovim executable not found")
    with tempfile.TemporaryDirectory(prefix="draftsman-gifs-") as temp:
        temp = Path(temp)
        source, target = temp / "input.json", temp / "frames.json"
        source.write_text(json.dumps(cfg))
        env = dict(
            os.environ,
            DRAFTSMAN_GIF_INPUT=str(source),
            DRAFTSMAN_GIF_OUTPUT=str(target),
            NVIM_LOG_FILE=str(temp / "nvim.log"),
        )
        # Paths go through an environment variable instead of Ex/shell interpolation.
        env["DRAFTSMAN_GIF_ROOT"] = str(ROOT)
        proc = subprocess.run(
            [
                nvim,
                "--headless",
                "-n",
                "-u",
                "NONE",
                "-i",
                "NONE",
                "-c",
                "lua vim.opt.rtp:prepend(vim.env.DRAFTSMAN_GIF_ROOT); dofile(vim.env.DRAFTSMAN_GIF_ROOT .. '/scripts/gifs/capture.lua')",
            ],
            cwd=ROOT,
            env=env,
            capture_output=True,
            text=True,
            timeout=60,
        )
        if proc.returncode or not target.exists():
            raise RuntimeError(
                f"Neovim capture failed:\n{proc.stdout}\n{proc.stderr}"
            )
        scenes = json.loads(target.read_text())
    for scene in scenes:
        frames = scene["frames"]
        size = dimensions(frames, cfg, cell_width)
        history, images = [], []
        for frame in frames:
            if frame["key"]:
                history.append(frame["key"])
            images.append(
                render_frame(frame, cfg, font, size, cell_width, history)
            )
        # A shared palette prevents color flicker and leaves plenty of antialias shades.
        sample = Image.new("RGB", (size[0], size[1] * min(8, len(images))))
        for i in range(min(8, len(images))):
            sample.paste(
                images[
                    round(
                        i * (len(images) - 1) / max(1, min(8, len(images)) - 1)
                    )
                ],
                (0, size[1] * i),
            )
        palette = sample.quantize(colors=256)
        images = [
            img.quantize(palette=palette, dither=Image.Dither.NONE)
            for img in images
        ]
        durations = [
            max(10, round(frame["duration"] / 10) * 10) for frame in frames
        ]
        path = output / f"{scene['name']}.gif"
        images[0].save(
            path,
            save_all=True,
            append_images=images[1:],
            duration=durations,
            loop=cfg["loop"],
            optimize=True,
            disposal=1,
        )
        print(
            f"{path.relative_to(ROOT) if path.is_relative_to(ROOT) else path}: {size[0]}×{size[1]}, {sum(durations)/1000:.2f}s, {path.stat().st_size/1024:.0f} KiB"
        )
        if args.frames_dir:
            args.frames_dir.mkdir(parents=True, exist_ok=True)
            (args.frames_dir / f"{scene['name']}.json").write_text(
                json.dumps(scene, ensure_ascii=False, indent=2) + "\n"
            )


if __name__ == "__main__":
    main()
