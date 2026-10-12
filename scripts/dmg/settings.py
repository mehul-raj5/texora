# dmgbuild settings for Texora. Used by scripts/make-dmg.sh:
#   dmgbuild -s scripts/dmg/settings.py -D app=dist/Texora.app -D background=… "Texora" out.dmg
import os

application = defines.get("app", "dist/Texora.app")  # noqa: F821 (provided by dmgbuild)
appname = os.path.basename(application)

format = "UDZO"
compression_level = 9
filesystem = "HFS+"
size = None

files = [application]
symlinks = {"Applications": "/Applications"}

icon = defines.get("volume_icon", "Resources/AppIcon.icns")  # noqa: F821
background = defines.get("background", "scripts/dmg/background.tiff")  # noqa: F821

window_rect = ((200, 140), (660, 460))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None
icon_size = 112
text_size = 13
label_pos = "bottom"
icon_locations = {
    appname: (165, 165),
    "Applications": (495, 165),
}
