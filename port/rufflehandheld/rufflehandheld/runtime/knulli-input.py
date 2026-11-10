#!/usr/bin/env python3
"""Use Knulli's own controller configuration for launches outside Ports."""
import argparse
import sys


def main(argv=None):
    parser = argparse.ArgumentParser()
    for player in range(1, 9):
        for field in ("index", "guid", "name", "devicepath", "nbbuttons", "nbhats", "nbaxes"):
            kind = int if field in ("index", "nbbuttons", "nbhats", "nbaxes") else str
            parser.add_argument(f"-p{player}{field}", type=kind)
    args, _ = parser.parse_known_args(argv)
    if not any(getattr(args, f"p{player}index") is not None for player in range(1, 9)):
        print("Knulli input: no controller information received from EmulationStation", file=sys.stderr)
        return 1
    try:
        from configgen.controller import Controller, generate_sdl_game_controller_config
        controllers = Controller.load_for_players(8, args)
        mapping = generate_sdl_game_controller_config(controllers)
        if not mapping.strip():
            raise ValueError("no matching controller configuration")
    except (ImportError, AttributeError, OSError, ValueError) as error:
        print(f"Knulli input: {error}; using PortMaster mapping", file=sys.stderr)
        return 1
    print(mapping)
    print(f"Knulli input: loaded {len(controllers)} controller(s) from EmulationStation", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
