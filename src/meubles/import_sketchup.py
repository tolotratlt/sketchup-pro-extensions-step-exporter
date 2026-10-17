"""Convertit une hiérarchie exportée de SketchUp (export_freecad.rb) en STEP, via FreeCAD.

    SU_JSON=modele.json [SU_STEP=modele.step] FreeCADCmd.exe import_sketchup.py

Structure du STEP (identique à l'Outliner SketchUp, rien n'est renommé ni aplati) :
    racine « titre du modèle » > groupes/composants > ... > pièces
    - chaque groupe / composant avec enfants -> assemblage STEP nommé comme dans SketchUp ;
    - chaque pièce -> produit STEP nommé par son nom d'instance (« Côté gauche », « Panneau »),
      solide B-rep exact. Les pièces identiques ne partagent pas leur produit : c'est ce qui permet
      aux lecteurs (FreeCAD, build123d) d'afficher le nom d'instance et non celui de la définition.
Les noms non ASCII sont encodés \\X2\\...\\X0\\ (ISO 10303-21).
"""

import json
import os
import sys

import FreeCAD as App
import Part

# Sans DuplicateLabels, FreeCAD renomme le 2e « Panneau » en « Panneau001 » avant l'export.
# FreeCADCmd enregistre les paramètres dans le user.cfg partagé avec l'interface : restauré en fin de script.
DOC_PARAMS = App.ParamGet("User parameter:BaseApp/Preferences/Document")


def make_face(face):
    wires = [Part.makePolygon([App.Vector(*p) for p in loop] + [App.Vector(*loop[0])])
             for loop in [face["outer"], *face.get("inner", [])]]
    return Part.makeFace(wires, "Part::FaceMakerBullseye")


def make_shape(faces):
    shell = Part.Shell([make_face(f) for f in faces])
    shell.sewShape()
    if shell.isClosed():
        solid = Part.Solid(shell)
        if solid.Volume < 0:
            solid.reverse()
        return solid
    return shell


class Builder:
    def __init__(self, doc, data):
        self.doc = doc
        self.data = data
        self.shapes = {}  # nom de définition -> Part.Shape (calculée une fois)
        self.renamed = []

    def shape(self, name):
        if name not in self.shapes:
            self.shapes[name] = make_shape(self.data["definitions"][name]["faces"])
        return self.shapes[name]

    def set_label(self, obj, label):
        obj.Label = label
        if obj.Label != label:
            self.renamed.append((label, obj.Label))

    def leaf(self, label, definition_name):
        obj = self.doc.addObject("Part::Feature", "Piece")
        obj.Shape = self.shape(definition_name).copy()
        self.set_label(obj, label)
        obj.addProperty("App::PropertyString", "SketchUp_Definition", "SketchUp", "Définition SketchUp")
        obj.SketchUp_Definition = definition_name
        return obj

    def build(self, node):
        children = node["children"]
        if children:
            obj = self.doc.addObject("App::LinkGroup", "Assembly")
            elements = [self.build(child) for child in children]
            if self.data["definitions"][node["definition"]]["faces"]:  # géométrie propre à l'assemblage
                elements.append(self.leaf(node["definition"], node["definition"]))
            obj.ElementList = elements
            self.set_label(obj, node["name"])
        else:
            obj = self.leaf(node["name"], node["definition"])
        obj.Placement = App.Placement(App.Matrix(*node["matrix"]))
        return obj


def tree(obj, depth=0, lines=None):
    lines = [] if lines is None else lines
    lines.append(f"{'  ' * depth}- {obj.Label}")
    for child in getattr(obj, "ElementList", None) or []:
        tree(child, depth + 1, lines)
    return lines


def step_ascii(path):
    """FreeCAD écrit l'UTF-8 brut ; les lecteurs STEP (dont FreeCAD avec interface) le décodent
    souvent en Latin-1 (« Ã‰tagÃ¨res »). On encode selon la norme : É -> \\X2\\00C9\\X0\\."""
    def encode(ch):
        code = ord(ch)
        return f"\\X2\\{code:04X}\\X0\\" if code <= 0xFFFF else f"\\X4\\{code:08X}\\X0\\"

    with open(path, encoding="utf-8") as f:
        text = f.read()
    with open(path, "w", encoding="ascii", newline="") as f:
        f.write("".join(ch if ord(ch) < 128 else encode(ch) for ch in text))


def main():
    json_path = os.environ["SU_JSON"]
    base = os.path.splitext(json_path)[0]
    step_path = os.environ.get("SU_STEP", base + ".step")

    with open(json_path, encoding="utf-8") as f:
        data = json.load(f)
    if data.get("format") != "sketchup-hierarchy":
        raise SystemExit(f"Format inattendu : {data.get('format')}")

    doc = App.newDocument("SketchUpExport")
    builder = Builder(doc, data)
    # Racine = le modèle SketchUp (l'export STEP ignore le placement des objets racines).
    model = doc.addObject("App::LinkGroup", "Model")
    builder.set_label(model, data["source"].get("title") or os.path.basename(base))
    model.ElementList = [builder.build(node) for node in data["roots"]]
    doc.recompute()

    import Import
    Import.export([model], step_path)
    step_ascii(step_path)

    print("\n".join(tree(model)))
    if builder.renamed:
        print("ATTENTION labels modifiés par FreeCAD :", builder.renamed)
    print("STEP :", step_path)
    App.closeDocument(doc.Name)


_previous = DOC_PARAMS.GetBool("DuplicateLabels", False)
DOC_PARAMS.SetBool("DuplicateLabels", True)
try:
    main()
finally:
    DOC_PARAMS.SetBool("DuplicateLabels", _previous)
    sys.stdout.flush()
