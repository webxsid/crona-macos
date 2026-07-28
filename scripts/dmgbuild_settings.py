import os
import plistlib

application = defines["app"]  # noqa: F821
appname = os.path.basename(application)
background = defines["background"]  # noqa: F821
volume_name = defines.get("volume_name", "Crona")  # noqa: F821
format = defines.get("format", "UDZO")  # noqa: F821
size = defines.get("size", None)  # noqa: F821


def icon_from_app(app_path):
    plist_path = os.path.join(app_path, "Contents", "Info.plist")
    with open(plist_path, "rb") as f:
        plist = plistlib.load(f)
    icon_name = plist["CFBundleIconFile"]
    icon_root, icon_ext = os.path.splitext(icon_name)
    if not icon_ext:
        icon_ext = ".icns"
    return os.path.join(app_path, "Contents", "Resources", icon_root + icon_ext)


files = [application]
symlinks = {"Applications": "/Applications"}
badge_icon = icon_from_app(application)

icon_locations = {
    appname: (170, 235),
    "Applications": (530, 235),
}

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 180
window_rect = ((120, 140), (720, 460))
default_view = "icon-view"
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False

arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100
scroll_position = (0, 0)
label_pos = "bottom"
text_size = 13
icon_size = 128
