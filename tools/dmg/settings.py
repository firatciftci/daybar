import json
import os
import plistlib

options = globals()["defines"]
app = options["app"]
here = options["dir"]
name = os.path.basename(app)

with open(os.path.join(here, "dmg.json"), encoding="utf-8") as file:
    design = json.load(file)

with open(os.path.join(app, "Contents", "Info.plist"), "rb") as file:
    info = plistlib.load(file)

icon_file = info.get("CFBundleIconFile")
if icon_file:
    icon_path = os.path.join(
        app,
        "Contents",
        "Resources",
        icon_file if icon_file.endswith(".icns") else icon_file + ".icns",
    )
    icon = icon_path if os.path.isfile(icon_path) else None

format = "ULFO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
background = os.path.join(here, "background.tiff")

window_rect = ((200, 120), (design["width"], design["height"] + 32))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False

arrange_by = None
icon_size = design["iconSize"]
text_size = 13
label_pos = "bottom"
icon_locations = {
    name: tuple(design["app"]),
    "Applications": tuple(design["applications"]),
}
