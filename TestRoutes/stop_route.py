#!/usr/bin/env python3
"""Stops location playback in the iOS Simulator, started by play_route.py or by hand.

    python3 TestRoutes/stop_route.py
    python3 TestRoutes/stop_route.py --device "iPhone 18 Pro"

Wraps `xcrun simctl location <device> clear`. The simulator then has no simulated location
until you set or play one again.
"""
import argparse
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--device", default="booted", help="simulator name or UDID (default: booted)")
    args = parser.parse_args()

    result = subprocess.run(["xcrun", "simctl", "location", args.device, "clear"], text=True, capture_output=True)
    if result.returncode != 0:
        sys.exit(f"simctl location clear failed: {result.stderr.strip() or result.stdout.strip()}")
    print("Stopped location playback.")


if __name__ == "__main__":
    main()
