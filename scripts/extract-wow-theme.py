"""Extract quest UI sounds, fonts and textures from a local World of Warcraft install into ~/.questlog/theme.

Usage: uv run --with pillow scripts/extract-wow-theme.py <libcasc path> [game dir] [product]
Reads the game's own CASC storage through CascLib; BLP textures are converted to PNG.
Without a game dir it looks in the usual install folders; without a product it uses the one installed there
(wow, wow_classic, wowf...). scripts/setup-theme.sh builds CascLib and runs this for you.
"""
import ctypes
import io
import os
import sys
from pathlib import Path

from PIL import Image

LIB = sys.argv[1]
CANDIDATES = ["/Applications/World of Warcraft", "~/Applications/World of Warcraft", "~/Games/World of Warcraft"]


def find_game() -> str:
    for c in CANDIDATES:
        if (Path(c).expanduser() / ".build.info").exists():
            return str(Path(c).expanduser())
    sys.exit("World of Warcraft not found; pass its folder: extract-wow-theme.py <libcasc> <game dir>")


def installed_product(game: str) -> str:
    """The active product in the install's .build.info (last column is Product)."""
    lines = (Path(game) / ".build.info").read_text().splitlines()
    cols = [c.split("!")[0] for c in lines[0].split("|")]
    for row in lines[1:]:
        vals = dict(zip(cols, row.split("|")))
        if vals.get("Active") == "1" and vals.get("Product"):
            return vals["Product"]
    return "wow"


GAME = os.path.expanduser(sys.argv[2]) if len(sys.argv) > 2 else find_game()
PRODUCT = sys.argv[3] if len(sys.argv) > 3 else installed_product(GAME)
THEME = Path(os.environ.get("QUESTLOG_HOME", Path.home() / ".questlog")) / "theme"
print(f"Reading {GAME} ({PRODUCT})")

# FileDataIDs from the community listfile (wowdev/wow-listfile).
SOUNDS = {
    "open": 567504,       # sound/interface/iquestlogopena.ogg
    "close": 567508,      # sound/interface/iquestlogclosea.ogg
    "accept": 567400,     # sound/interface/iquestactivate.ogg
    "objective": 567516,  # sound/interface/iquestupdate.ogg
    "complete": 567439,   # sound/interface/iquestcomplete.ogg
    "levelup": 567431,    # sound/interface/levelup.ogg
    "abandon": 567459,    # sound/interface/igquestfailed.ogg
    "offer": 567472,      # sound/interface/iabilitiesturnpagea.ogg (page turn when a quest window opens)
}
FONTS = {"ui": 615960, "title": 615962}  # fonts/frizqt__.ttf, fonts/morpheus.ttf
TEXTURES = {
    "parchment": 530420,          # interface/questframe/questbg.blp
    "questbook": 530421,          # interface/questframe/questbookbg.blp
    "button-up": 130828,          # interface/buttons/ui-panel-button-up.blp
    "button-down": 130825,
    "button-highlight": 130826,
    "button-disabled": 130824,
    "scroll-up": 130857,          # interface/buttons/ui-scrollbar-scrollupbutton-up.blp
    "scroll-down": 130853,
    "scroll-knob": 130849,
    "frame-metal": 2325363,       # interface/framegeneral/uiframemetal.blp
    "frame-metal-vertical": 2325366,
    "details-topleft": 308713,    # classic quest details corners
    "details-topright": 308714,
    "details-botleft": 307443,
    "details-botright": 307445,
    "questlog-left": 309665,      # interface/questframe/ui-questlogdualpane-left.blp
    "questlog-right": 309666,
    "book-icon": 136797,          # interface/questframe/ui-questlog-bookicon.blp (quest log portrait)
    "title-highlight": 136810,
    "bullet": 136788,
    "horizontal-break": 136783,
    "red-button": 1536801,        # interface/buttons/128redbutton.blp
    "close-up": 130832,           # interface/buttons/ui-panel-minimizebutton-up.blp
    "close-down": 130830,
    "close-highlight": 130831,
    "hide-up": 331604,            # interface/buttons/ui-panel-hidebutton-up.blp (minimize)
    "hide-down": 331603,
    "options": 851903,            # interface/buttons/ui-optionsbutton.blp (gear)
}

casc = ctypes.CDLL(LIB)
casc.CascOpenStorage.argtypes = [ctypes.c_char_p, ctypes.c_uint32, ctypes.POINTER(ctypes.c_void_p)]
casc.CascOpenStorage.restype = ctypes.c_bool
casc.CascOpenFile.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.POINTER(ctypes.c_void_p)]
casc.CascOpenFile.restype = ctypes.c_bool
casc.CascGetFileSize.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
casc.CascGetFileSize.restype = ctypes.c_uint32
casc.CascReadFile.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32, ctypes.POINTER(ctypes.c_uint32)]
casc.CascReadFile.restype = ctypes.c_bool
casc.CascCloseFile.argtypes = [ctypes.c_void_p]
casc.CascCloseStorage.argtypes = [ctypes.c_void_p]
casc.GetCascError.restype = ctypes.c_uint32
CASC_OPEN_BY_FILEID = 3

storage = ctypes.c_void_p()
if not casc.CascOpenStorage(f"{GAME}*{PRODUCT}".encode(), 0, ctypes.byref(storage)):
    sys.exit(f"Could not open CASC storage at {GAME} ({PRODUCT}): error {casc.GetCascError()}")


def read(file_id: int) -> bytes:
    handle = ctypes.c_void_p()
    if not casc.CascOpenFile(storage, ctypes.c_void_p(file_id), 0, CASC_OPEN_BY_FILEID, ctypes.byref(handle)):
        raise OSError(f"open {file_id}: error {casc.GetCascError()}")
    try:
        size = casc.CascGetFileSize(handle, None)
        buf = ctypes.create_string_buffer(size)
        got = ctypes.c_uint32()
        if not casc.CascReadFile(handle, buf, size, ctypes.byref(got)):
            raise OSError(f"read {file_id}: error {casc.GetCascError()}")
        return buf.raw[: got.value]
    finally:
        casc.CascCloseFile(handle)


def blp_image(data: bytes) -> Image.Image:
    """Pillow reads palette and DXT BLPs; BLP2 encoding 3 (raw BGRA) is decoded here."""
    import struct
    if data[:4] == b"BLP2" and data[8] == 3:
        width, height = struct.unpack_from("<II", data, 12)
        offset = struct.unpack_from("<I", data, 20)[0]
        return Image.frombuffer("RGBA", (width, height), data[offset:offset + width * height * 4], "raw", "BGRA", 0, 1)
    return Image.open(io.BytesIO(data))


def save(path: Path, data: bytes):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    print(f"  {path.relative_to(THEME)}  ({len(data):,} bytes)")


ok = failed = 0
for group, items, ext in (("sounds", SOUNDS, "ogg"), ("fonts", FONTS, "ttf")):
    for name, fid in items.items():
        try:
            save(THEME / group / f"{name}.{ext}", read(fid)); ok += 1
        except OSError as e:
            print(f"  ! {group}/{name}: {e}"); failed += 1
for name, fid in TEXTURES.items():
    try:
        img = blp_image(read(fid))
        out = io.BytesIO()
        img.convert("RGBA").save(out, "PNG")
        save(THEME / "textures" / f"{name}.png", out.getvalue()); ok += 1
    except Exception as e:  # noqa: BLE001 - report and keep going
        print(f"  ! textures/{name}: {e}"); failed += 1

# Assemble the quest window from the four quest-details pieces, with the portrait ring painted over
# (the title bar and left border are extended across it).
try:
    tex = THEME / "textures"
    full = Image.new("RGBA", (384, 512), (0, 0, 0, 0))
    for name, pos in (("topleft", (0, 0)), ("topright", (256, 0)), ("botleft", (0, 256)), ("botright", (256, 256))):
        full.alpha_composite(Image.open(tex / f"details-{name}.png"), pos)
    frame = full.copy()
    frame.paste(full.crop((72, 0, 142, 76)), (4, 0))
    frame.paste(Image.new("RGBA", (7, 76), (0, 0, 0, 0)), (0, 0))
    frame.paste(full.crop((0, 90, 20, 152)), (0, 14))
    frame.paste(Image.new("RGBA", (9, 14), (0, 0, 0, 0)), (0, 0))
    # Without the portrait the dark band under the title bar (rows 37-70) is empty: cut it out.
    cut = Image.new("RGBA", (384, 512 - 34), (0, 0, 0, 0))
    cut.paste(frame.crop((0, 0, 384, 37)), (0, 0))
    cut.paste(frame.crop((0, 71, 384, 512)), (0, 37))
    cut.save(tex / "quest-frame.png")
    print("  textures/quest-frame.png  (assembled)")
except OSError as e:
    print(f"  ! textures/quest-frame: {e}"); failed += 1

# The quest log frame as one 682x440 image, so the log window can stretch it with CSS border-image.
try:
    tex = THEME / "textures"
    log = Image.new("RGBA", (682, 440), (0, 0, 0, 0))
    log.alpha_composite(Image.open(tex / "questlog-left.png").convert("RGBA").crop((0, 0, 512, 440)), (0, 0))
    log.alpha_composite(Image.open(tex / "questlog-right.png").convert("RGBA").crop((0, 0, 170, 440)), (512, 0))
    log.save(tex / "questlog-frame.png")
    print("  textures/questlog-frame.png  (assembled)")
except OSError as e:
    print(f"  ! textures/questlog-frame: {e}"); failed += 1

casc.CascCloseStorage(storage)
print(f"Extracted {ok} files, {failed} failed, into {THEME}")
