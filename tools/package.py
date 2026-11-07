"""Build the ready-to-install zip: VoidShieldVortex-<version>.zip at the project root, holding just
the addon folder (VoidShieldVortex/ with its .toc, .lua and media/). Unzip it into
World of Warcraft/_retail_/Interface/AddOns, or upload it to CurseForge as-is.

    python tools/package.py              # build the zip
    python tools/package.py --install    # build it and install it into your AddOns folder
"""
import os, re, shutil, sys, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = 'VoidShieldVortex'
ADDON = os.path.join(ROOT, NAME)
KEEP = ('.toc', '.lua', '.tga', '.blp', '.ogg', '.mp3', '.ttf', '.xml')   # only what the game loads
ADDONS = r'C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns'

toc = open(os.path.join(ADDON, NAME + '.toc'), encoding='utf8').read()
version = re.search(r'^## Version:\s*(\S+)', toc, re.M).group(1)
files = []
for base, dirs, names in os.walk(ADDON):
    dirs[:] = sorted(d for d in dirs if not d.startswith('.'))
    for n in sorted(names):
        if n.lower().endswith(KEEP):
            files.append(os.path.relpath(os.path.join(base, n), ROOT))
out = os.path.join(ROOT, f'{NAME}-{version}.zip')
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for f in files:
        z.write(os.path.join(ROOT, f), f.replace(os.sep, '/'))
print(f'{out}: {len(files)} files, {os.path.getsize(out) // 1024} KB')

if '--install' in sys.argv:
    dest = os.path.join(ADDONS, NAME)
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    with zipfile.ZipFile(out) as z:
        z.extractall(ADDONS)
    print('installed to', dest, '- fully restart the game (not just /reload) to load new files')
