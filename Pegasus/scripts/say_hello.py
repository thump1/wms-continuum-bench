#!/usr/bin/env python3
import sys

if len(sys.argv) != 2:
    print(f"Usage: {sys.argv[0]} <name>", file=sys.stderr)
    sys.exit(1)

name = sys.argv[1]
print(f"Hello, {name}, from Pegasus on HTCondor!")
