#!/usr/bin/env python3
"""Apply runtime patches for StreamFlow 0.1.6 on macOS.

Patch 1 — container.py: Docker Desktop writes deprecation warnings to stdout,
polluting the container ID. Fix: take only the last line of stdout.

Patch 2 — token_processor.py: macOS /tmp -> /private/tmp symlink causes glob
path validation to fail. Fix: compare against os.path.realpath() of job dirs.
"""
import os, sys, site

pkgs = site.getsitepackages()[0]
sf = os.path.join(pkgs, "streamflow")

# Patch 1: container.py — Docker container ID
path1 = os.path.join(sf, "deployment", "connector", "container.py")
old1 = "                    self.containerIds.append(stdout.decode().strip())"
new1 = """\
                    # Take only the last line: Docker Desktop may print
                    # deprecation warnings (e.g. --disable-content-trust)
                    # to stdout before the container ID.
                    container_id = stdout.decode().strip().splitlines()[-1]
                    self.containerIds.append(container_id)"""

# Patch 2: token_processor.py — macOS /tmp symlink
path2 = os.path.join(sf, "cwl", "token_processor.py")
old2 = """\
    if not (effective_path.startswith(job.output_directory) or
            effective_path.startswith(job.input_directory) or
            context.data_manager.get_data_locations(resource, path)):"""
new2 = """\
    real_output_dir = os.path.realpath(job.output_directory)
    real_input_dir = os.path.realpath(job.input_directory)
    if not (effective_path.startswith(job.output_directory) or
            effective_path.startswith(job.input_directory) or
            effective_path.startswith(real_output_dir) or
            effective_path.startswith(real_input_dir) or
            context.data_manager.get_data_locations(resource, path)):"""

patches = [(path1, old1, new1, "container.py"), (path2, old2, new2, "token_processor.py")]

for path, old, new, name in patches:
    with open(path) as f:
        content = f.read()
    if new in content:
        print(f"  {name}: already patched")
    elif old in content:
        content = content.replace(old, new)
        with open(path, "w") as f:
            f.write(content)
        print(f"  {name}: patched")
    else:
        print(f"  {name}: WARNING — expected code not found, patch skipped")
        sys.exit(1)

print("All patches applied.")
