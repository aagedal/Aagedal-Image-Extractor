#!/usr/bin/env python3
"""Bundle cjxl and its transitive non-system dylibs, independent of Homebrew paths."""
import argparse
from pathlib import Path
import shutil
import subprocess


def run(*args):
    return subprocess.check_output(args, text=True)


def rpaths(binary):
    lines = run("otool", "-l", str(binary)).splitlines()
    for index, line in enumerate(lines):
        if line.strip() == "cmd LC_RPATH":
            yield lines[index + 2].strip().split(" (offset", 1)[0].removeprefix("path ")


def expand(path, loader, executable):
    return Path(path.replace("@loader_path", str(loader.parent))
                .replace("@executable_path", str(executable.parent)))


def prepare(source, destination):
    source = source.resolve(strict=True)
    destination.mkdir(parents=True, exist_ok=True)
    libraries = destination / "cjxl-lib"
    libraries.mkdir(exist_ok=True)
    queue = [(source, destination / "cjxl", True)]
    seen = {}
    inherited = [expand(p, source, source) for p in rpaths(source)]
    while queue:
        original, bundled, is_executable = queue.pop(0)
        if bundled in seen:
            if seen[bundled] != original:
                raise RuntimeError(f"Conflicting dependency basename: {bundled.name}")
            continue
        seen[bundled] = original
        bundled.unlink(missing_ok=True)
        shutil.copy2(original, bundled)
        subprocess.run(["codesign", "--remove-signature", str(bundled)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        search = [expand(p, original, source) for p in rpaths(original)] + inherited
        dependencies = [line.strip().split(" (compatibility", 1)[0]
                        for line in run("otool", "-L", str(original)).splitlines()[1:]]
        for dependency in dependencies:
            if dependency.startswith(("/usr/lib/", "/System/")):
                continue
            if dependency.startswith("@rpath/"):
                relative = dependency.removeprefix("@rpath/")
                resolved = next((directory / relative for directory in search
                                 if (directory / relative).is_file()), None)
            else:
                resolved = expand(dependency, original, source)
            if resolved is None or not resolved.is_file():
                raise RuntimeError(f"Cannot resolve {dependency} from {original}")
            resolved = resolved.resolve()
            if resolved == original:  # A dylib's install name is listed as its first dependency.
                continue
            queue.append((resolved, libraries / resolved.name, False))
            replacement = ("@loader_path/cjxl-lib/" if is_executable else "@loader_path/") + resolved.name
            subprocess.run(["install_name_tool", "-change", dependency, replacement, str(bundled)], check=True)
        if not is_executable:
            subprocess.run(["install_name_tool", "-id", "@rpath/" + bundled.name, str(bundled)], check=True)
    # Retain Homebrew formula licenses/notices for every redistributed component.
    notices = destination / "licenses"
    for original in set(seen.values()):
        formula = next((parent for parent in original.parents
                        if (parent / "INSTALL_RECEIPT.json").is_file()), original.parent)
        component = notices / (formula.parent.name + "-" + formula.name)
        for candidate in formula.iterdir():
            if candidate.is_file() and candidate.name.lower().startswith(("license", "copying", "notice", "authors")):
                component.mkdir(parents=True, exist_ok=True)
                notice = component / candidate.name
                notice.unlink(missing_ok=True)
                shutil.copy2(candidate, notice)
    # Ad-hoc signing makes the prepared tools runnable for verification. The app build re-signs them.
    for binary in sorted(seen, key=lambda path: path == destination / "cjxl"):
        subprocess.run(["codesign", "--force", "--sign", "-", str(binary)], check=True)
    print(f"Prepared cjxl and {len(seen) - 1} libraries in {destination}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(shutil.which("cjxl") or "/opt/homebrew/bin/cjxl"))
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent.parent / "vendor/cjxl")
    args = parser.parse_args()
    prepare(args.source, args.output.resolve())
