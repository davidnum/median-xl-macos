import argparse
import hashlib
import json
import os
import shutil
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

MANIFEST_URL = "https://launcher.median-xl.com/mxl/release/public/manifest"
USER_AGENT = "median-xl-macos-updater"
RETRIES = 4


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    return urllib.request.urlopen(request, timeout=60)


def sha1_of(path):
    digest = hashlib.sha1()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


class Updater:
    def __init__(self, game, keep_local):
        self.game = game
        self.keep_local = keep_local
        self.state_file = game / ".mxl-update-state.json"
        self.tmp = game / ".mxl-update-tmp"
        self.backup = game / ".mxl-update-backup"
        try:
            self.state = json.loads(self.state_file.read_text())
        except (OSError, ValueError):
            self.state = {"files": {}}
        self.cache = self.state.setdefault("files", {})

    def local_sha1(self, name, path):
        st = path.stat()
        known = self.cache.get(name)
        if known and known["size"] == st.st_size and known["mtime"] == st.st_mtime:
            return known["sha1"]
        sha1 = sha1_of(path)
        self.cache[name] = {"size": st.st_size, "mtime": st.st_mtime, "sha1": sha1}
        return sha1

    def target(self, name):
        return self.game.joinpath(*name.replace("\\", "/").split("/"))

    def outdated(self, manifest):
        result = []
        for entry in manifest["files"]:
            name = entry["name"]
            if name.lower() in self.keep_local:
                continue
            path = self.target(name)
            if not path.exists() or self.local_sha1(name, path) != entry["sha1"]:
                result.append(entry)
        return result

    def fetch_verified(self, entry, tmp):
        for attempt in range(1, RETRIES + 1):
            try:
                digest = hashlib.sha1()
                with fetch(entry["url"]) as response, open(tmp, "wb") as out:
                    for chunk in iter(lambda: response.read(1 << 20), b""):
                        digest.update(chunk)
                        out.write(chunk)
                if tmp.stat().st_size == entry["size"] and digest.hexdigest() == entry["sha1"]:
                    return
                problem = "downloaded file does not match the manifest"
            except (OSError, urllib.error.URLError) as error:
                problem = str(error)
            tmp.unlink(missing_ok=True)
            if attempt == RETRIES:
                raise RuntimeError(f"{entry['name']}: {problem}")
            print(f"    retry {attempt}/{RETRIES - 1} in {attempt * 5}s: {problem}", flush=True)
            time.sleep(attempt * 5)

    def download(self, entry):
        path = self.target(entry["name"])
        path.parent.mkdir(parents=True, exist_ok=True)
        self.tmp.mkdir(exist_ok=True)
        tmp = self.tmp / path.name
        self.fetch_verified(entry, tmp)
        if path.exists():
            self.backup.mkdir(exist_ok=True)
            shutil.copy2(path, self.backup / path.name)
        os.replace(tmp, path)
        self.cache.pop(entry["name"], None)
        self.local_sha1(entry["name"], path)

    def save(self, tag):
        self.state["tag"] = tag
        self.state_file.write_text(json.dumps(self.state))


def main():
    parser = argparse.ArgumentParser(description="Install or update Median XL from the official release manifest.")
    parser.add_argument("--game", required=True, type=Path, help="Median XL game folder")
    parser.add_argument("--keep", default="", help="comma-separated file names to never replace, e.g. glide3x.dll,ddraw.dll")
    parser.add_argument("--check", action="store_true", help="only report what would change (exit code 1 if outdated)")
    args = parser.parse_args()

    try:
        manifest = json.load(fetch(MANIFEST_URL))
    except Exception as error:
        print(f"manifest unavailable: {error}")
        return 2

    keep = {n.strip().lower() for n in args.keep.split(",") if n.strip()}
    updater = Updater(args.game, keep)
    outdated = updater.outdated(manifest)
    if not outdated:
        updater.save(manifest["tag"])
        print(f"up to date: {manifest['tag']}")
        return 0

    total_mb = sum(e["size"] for e in outdated) / 1048576
    print(f"update {updater.state.get('tag', 'none')} -> {manifest['tag']}: {len(outdated)} files, {total_mb:.1f} MB")
    if args.check:
        return 1
    if updater.state.get("partial") != manifest["tag"] and updater.backup.exists():
        shutil.rmtree(updater.backup)
    updater.state["partial"] = manifest["tag"]
    try:
        for i, entry in enumerate(outdated, 1):
            print(f"  [{i}/{len(outdated)}] {entry['name']} ({entry['size'] / 1048576:.1f} MB)", flush=True)
            updater.download(entry)
    except RuntimeError as error:
        updater.state_file.write_text(json.dumps(updater.state))
        print(f"download failed: {error}")
        return 3
    shutil.rmtree(updater.tmp, ignore_errors=True)
    updater.state.pop("partial", None)
    updater.save(manifest["tag"])
    print(f"updated to {manifest['tag']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
