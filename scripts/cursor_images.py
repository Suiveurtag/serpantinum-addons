"""Read cursor images and animations, preserving Xcursor sizes and click points."""
import io
import struct
from pathlib import Path

from PIL import Image, ImageOps

MAX_BYTES = 32 * 1024 * 1024
MAX_FRAMES = 256
MAX_PIXELS = 16_000_000
IMAGE_TYPE = 0xFFFD0002


def read_bytes(path):
    path = Path(path)
    if path.stat().st_size > MAX_BYTES:
        raise ValueError("Cursor file exceeds 32 MiB")
    return path.read_bytes()


def xcursor_frames(data):
    if len(data) < 16 or data[:4] != b'Xcur':
        raise ValueError("Invalid Xcursor header")
    _, header, _, count = struct.unpack_from('<4I', data)
    if header < 16 or count > 8192 or header + count * 12 > len(data):
        raise ValueError("Invalid Xcursor table")
    frames = []
    pixels = 0
    for index in range(count):
        kind, nominal, offset = struct.unpack_from('<3I', data, header + index * 12)
        if kind != IMAGE_TYPE:
            continue
        if offset + 36 > len(data):
            raise ValueError("Truncated Xcursor image")
        chunk, image_type, size, _, width, height, x, y, delay = struct.unpack_from('<9I', data, offset)
        pixels += width * height
        end = offset + chunk + width * height * 4
        if (chunk < 36 or image_type != kind or size != nominal or not 0 < width <= 1024
                or not 0 < height <= 1024 or x >= width or y >= height or end > len(data)
                or not 0 < nominal <= 1024 or pixels > MAX_PIXELS):
            raise ValueError("Invalid Xcursor image dimensions or click point")
        image = Image.frombytes('RGBa', (width, height), data[offset + chunk:end], 'raw', 'BGRa').convert('RGBA')
        frames.append((nominal, image, (x, y), max(10, min(delay or 100, 60000))))
        if len(frames) > MAX_FRAMES * 16:
            raise ValueError("Too many cursor frames")
    if not frames:
        raise ValueError("Cursor contains no images")
    return frames


def windows_cursor(data):
    if len(data) < 22:
        raise ValueError("Truncated Windows cursor")
    reserved, kind, count = struct.unpack_from('<3H', data)
    if reserved or kind not in (1, 2) or not 0 < count <= 256 or 6 + count * 16 > len(data):
        raise ValueError("Invalid Windows cursor header")
    entries = []
    for index in range(count):
        offset = 6 + index * 16
        width, height, _, _, hotx, hoty, length, position = struct.unpack_from('<4B2H2I', data, offset)
        if position + length > len(data):
            raise ValueError("Truncated Windows cursor image")
        entries.append((width or 256, height or 256, hotx, hoty, length, position))
    width, height, x, y, length, position = max(entries, key=lambda entry: entry[0] * entry[1])
    # Present CUR data as a one-image ICO so Pillow also decodes PNG-backed .cur files.
    icon = struct.pack('<3H', 0, 1, 1) + struct.pack('<4B2H2I', width % 256, height % 256, 0, 0, 1, 32, length, 22)
    with Image.open(io.BytesIO(icon + data[position:position + length])) as opened:
        if opened.size != (width, height):
            raise ValueError('Windows cursor image dimensions do not match its header')
        image = opened.convert('RGBA')
    hotspot = (min(x, width - 1), min(y, height - 1)) if kind == 2 else (0, 0)
    return (max(image.size), image, hotspot, 100)


def riff_chunks(data, start, end):
    while start + 8 <= end:
        kind, length = struct.unpack_from('<4sI', data, start)
        body = start + 8
        if body + length > end:
            raise ValueError("Truncated animated cursor chunk")
        yield kind, data[body:body + length]
        start = body + length + (length & 1)


def ani_frames(data):
    if len(data) < 12 or data[:4] != b'RIFF' or data[8:12] != b'ACON':
        raise ValueError("Invalid animated cursor header")
    end = struct.unpack_from('<I', data, 4)[0] + 8
    if end > len(data):
        raise ValueError("Truncated animated cursor")
    icons, rates, sequence, header = [], [], [], None
    for kind, body in riff_chunks(data, 12, end):
        if kind == b'anih':
            if len(body) < 36:
                raise ValueError("Invalid animation header")
            header = struct.unpack_from('<9I', body)
        elif kind in (b'rate', b'seq '):
            if len(body) % 4:
                raise ValueError("Invalid animation sequence")
            values = list(struct.unpack('<' + 'I' * (len(body) // 4), body))
            if kind == b'rate':
                rates = values
            else:
                sequence = values
        elif kind == b'LIST' and body[:4] == b'fram':
            for child, icon in riff_chunks(body, 4, len(body)):
                if child == b'icon':
                    icons.append(windows_cursor(icon))
                    if len(icons) > MAX_FRAMES:
                        raise ValueError("Too many animation frames")
    if not header or not icons or not header[8] & 1 or header[1] != len(icons):
        raise ValueError("Unsupported or incomplete animated cursor")
    steps = header[2] or len(icons)
    if steps > MAX_FRAMES:
        raise ValueError("Too many animation steps")
    order = sequence if header[8] & 2 else list(range(len(icons)))
    if len(order) != steps or any(index >= len(icons) for index in order) or (rates and len(rates) != steps):
        raise ValueError("Invalid animated cursor frame sequence")
    return [(icons[index][0], icons[index][1], icons[index][2],
             max(10, min(round((rates[step] if rates else header[7] or 6) * 1000 / 60), 60000)))
            for step, index in enumerate(order)]


def load_frames(path):
    data = read_bytes(path)
    if data[:4] == b'Xcur':
        return xcursor_frames(data)
    if data[:4] == b'RIFF' and data[8:12] == b'ACON':
        return ani_frames(data)
    if data[:4] in (b'\0\0\2\0', b'\0\0\1\0'):
        return [windows_cursor(data)]
    frames = []
    with Image.open(io.BytesIO(data)) as image:
        count = getattr(image, 'n_frames', 1)
        if count > MAX_FRAMES or image.width * image.height * count > MAX_PIXELS:
            raise ValueError("Cursor image or animation is too large")
        for index in range(count):
            image.seek(index)
            frame = ImageOps.exif_transpose(image).convert('RGBA')
            frames.append((max(frame.size), frame, (0, 0), max(10, min(int(image.info.get('duration', 100)), 60000))))
    return frames


def closest_frames(frames, size):
    nominal = min({frame[0] for frame in frames}, key=lambda value: (abs(value - size), -value))
    selected = [frame for frame in frames if frame[0] == nominal]
    if len(selected) > MAX_FRAMES:
        raise ValueError("Too many cursor frames at this size")
    return selected


def encode_frames(frames, hotspot=None):
    chunks = []
    sizes = sorted({frame[0] for frame in frames}) if len({frame[0] for frame in frames}) > 1 else [16, 24, 32, 48, 64, 96, 128]
    for size in sizes:
        for _, image, point, delay in closest_frames(frames, size):
            width, height = image.size
            ratio = size / max(width, height)
            target = (max(1, round(width * ratio)), max(1, round(height * ratio)))
            scaled = image.resize(target, Image.Resampling.LANCZOS)
            if hotspot is None:
                x, y = min(target[0] - 1, round(point[0] * ratio)), min(target[1] - 1, round(point[1] * ratio))
            else:
                x, y = round(hotspot[0] * (target[0] - 1)), round(hotspot[1] * (target[1] - 1))
            chunk = struct.pack('<9I', 36, IMAGE_TYPE, size, 1, *target, x, y, delay) + scaled.convert('RGBa').tobytes('raw', 'BGRa')
            chunks.append((size, chunk))
    header = struct.pack('<4I', 0x72756358, 16, 1, len(chunks))
    offset = 16 + len(chunks) * 12
    table, body = [], []
    for size, chunk in chunks:
        table.append(struct.pack('<3I', IMAGE_TYPE, size, offset))
        body.append(chunk)
        offset += len(chunk)
    if offset > MAX_BYTES:
        raise ValueError('Cursor animation exceeds 32 MiB after conversion')
    return header + b''.join(table) + b''.join(body)
