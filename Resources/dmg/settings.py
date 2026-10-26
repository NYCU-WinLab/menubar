# dmgbuild settings for the WinLab installer window.
#   dmgbuild -s Resources/dmg/settings.py -D app=<WinLab.app> "WinLab <version>" <out.dmg>
# background.tiff is background.svg at 1x and 2x (scripts/dmg-background.sh).
import os.path

app = defines["app"]
# The background path comes in as -D background=..., or defaults to the
# repository layout when dmgbuild runs from the repository root.
here = os.path.abspath("Resources/dmg")

files = [app]
symlinks = {"Applications": "/Applications"}
format = "UDZO"
filesystem = "HFS+"
background = defines.get("background", os.path.join(here, "background.tiff"))
icon_size = 128
text_size = 13
# The frame includes the 32 pt title bar; the content is 660 x 400.
window_rect = ((200, 120), (660, 432))
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
hide_extensions = [os.path.basename(app)]
icon_locations = {os.path.basename(app): (180, 182), "Applications": (480, 182)}
