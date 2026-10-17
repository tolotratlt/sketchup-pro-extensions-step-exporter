"""Vérifie qu'un STEP exporté de SketchUp se relit dans build123d avec la bonne hiérarchie.

    python check_step_build123d.py fichier.step

Affiche l'arbre (label, type, emprise en mm) tel que build123d le voit.
"""

import sys

from build123d import Compound, import_step


def show(shape, depth=0):
    bb = shape.bounding_box()
    kind = type(shape).__name__
    size = f"{bb.size.X:.1f} x {bb.size.Y:.1f} x {bb.size.Z:.1f}"
    print(f"{'  ' * depth}- {shape.label or '(sans nom)'}  [{kind}]  {size}  @ ({bb.min.X:.1f}, {bb.min.Y:.1f}, {bb.min.Z:.1f})")
    if isinstance(shape, Compound):
        for child in shape.children:
            show(child, depth + 1)


if __name__ == "__main__":
    root = import_step(sys.argv[1])
    show(root)
    leaves = [s for s in root.leaves] if hasattr(root, "leaves") else []
    print(f"\nFeuilles : {len(leaves)}  |  solides : {len(root.solids())}")
