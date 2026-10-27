"""Convertit une hiérarchie exportée de SketchUp (export_freecad.rb) en STEP, via FreeCAD.

    SU_JSON=modele.json [SU_STEP=modele.step] FreeCADCmd.exe import_sketchup.py

Structure du STEP (identique à l'Outliner SketchUp, rien n'est renommé ni aplati) :
    racine « titre du modèle » > groupes/composants > ... > pièces
    - chaque groupe / composant avec enfants -> assemblage STEP nommé comme dans SketchUp ;
    - chaque pièce -> produit STEP nommé par son nom d'instance (« Côté gauche », « Panneau »),
      solide B-rep exact. Les lecteurs (FreeCAD, build123d) affichent le nom du produit : deux
      instances d'une même définition ne partagent leur produit (et leur géométrie) que si elles
      portent le même nom, sinon chacune a le sien.
Les noms non ASCII sont encodés \\X2\\...\\X0\\ (ISO 10303-21).
"""

import json
import os
import sys
from collections import Counter

import FreeCAD as App
import Part

# La sortie est lue en UTF-8 par export_freecad.rb (sous Windows elle serait en cp1252).
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# Sans DuplicateLabels, FreeCAD renomme le 2e « Panneau » en « Panneau001 » avant l'export.
# FreeCADCmd enregistre les paramètres dans le user.cfg partagé avec l'interface : restauré en fin de script.
DOC_PARAMS = App.ParamGet("User parameter:BaseApp/Preferences/Document")


def mean_plane(points):
    """Plan moyen d'une boucle (normale de Newell, centre de gravité des sommets)."""
    normal = App.Vector()
    for a, b in zip(points, points[1:] + points[:1]):
        normal += App.Vector((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
    if normal.Length < 1e-12:
        return None, None
    center = sum(points, App.Vector()) * (1.0 / len(points))
    return center, normal.normalize()


def clean_loop(loop):
    """Sommets distincts (l'arrondi au µm peut fusionner deux sommets voisins)."""
    points = []
    for p in (App.Vector(*p) for p in loop):
        if not points or (p - points[-1]).Length > 1e-6:
            points.append(p)
    if len(points) > 1 and (points[0] - points[-1]).Length <= 1e-6:
        points.pop()
    return points


# Écart au plan (mm) au-delà duquel une face est refusée. SketchUp confond deux points à moins de
# 0,001" (0,0254 mm) et voit donc ces faces planes ; OpenCascade exige ~1e-7 mm.
# Modifiable avec la variable d'environnement SU_PLANAR_TOL.
PLANAR_TOL = float(os.environ.get("SU_PLANAR_TOL", "0.01"))


class FaceError(Exception):
    pass


def polygon_face(loops):
    return Part.makeFace([Part.makePolygon(points + points[:1]) for points in loops],
                         "Part::FaceMakerBullseye")


def make_face(face):
    """Face SketchUp -> (face OCC, écart corrigé en mm ou 0). Une face construite telle quelle n'est
    pas touchée ; une face très légèrement gauche (<= PLANAR_TOL) est projetée sur son plan moyen."""
    loops = [clean_loop(loop) for loop in [face["outer"], *face.get("inner", [])]]
    if any(len(points) < 3 for points in loops):
        raise FaceError("face dégénérée (moins de 3 sommets distincts)")
    try:
        return polygon_face(loops), 0.0
    except Exception as e:  # Base.FreeCADError (« Wires are not coplanar »), Part.OCCError
        reason = str(e)
    center, normal = mean_plane(loops[0])
    if normal is None:
        raise FaceError("face dégénérée (aire nulle)")
    deviation = max(abs((p - center).dot(normal)) for points in loops for p in points)
    if deviation > PLANAR_TOL:
        raise FaceError(f"face non plane, écart {deviation:.4f} mm > {PLANAR_TOL} mm ({reason})")
    loops = [[p - normal * (p - center).dot(normal) for p in points] for points in loops]
    return polygon_face(loops), deviation


def make_shape(faces, report):
    occ_faces = []
    for index, f in enumerate(faces):
        try:
            occ, deviation = make_face(f)
        except Exception as e:
            report["errors"].append((index, str(e)))
            continue
        if deviation:
            report["fixed"].append(deviation)
        occ_faces.append(occ)
    if report["errors"]:
        return None
    # Couture directe des faces : sur les maillages importés (milliers de triangles), passer
    # d'abord par Part.Shell coûte plus cher que la couture elle-même.
    shape = Part.Compound(occ_faces)
    shape.sewShape()
    shells = shape.Shells
    if len(shells) == 1 and len(shells[0].Faces) == len(shape.Faces) and shells[0].isClosed():
        solid = Part.Solid(shells[0])
        if solid.Volume < 0:
            solid.reverse()
        return solid
    return shape


class Builder:
    def __init__(self, doc, data):
        self.doc = doc
        self.data = data
        self.shapes = {}  # nom de définition -> Part.Shape (calculée une fois)
        self.renamed = []
        self.fixed = {}   # nom de définition -> écarts corrigés (mm)
        self.errors = {}  # nom de définition -> [(n° de face, raison)]
        self.where = {}   # nom de définition -> chemin de sa première instance
        self.shared = {}  # (définition, nom) -> Part::Feature partagée par plusieurs instances
        self.uses = Counter()
        for node in data["roots"]:
            self.count_leaves(node)

    def count_leaves(self, node):
        if node["children"]:
            for child in node["children"]:
                self.count_leaves(child)
            if self.data["definitions"][node["definition"]]["faces"]:
                self.uses[(node["definition"], node["definition"])] += 1
        else:
            self.uses[(node["definition"], node["name"])] += 1

    def shape(self, name):
        if name not in self.shapes:
            report = {"fixed": [], "errors": []}
            self.shapes[name] = make_shape(self.data["definitions"][name]["faces"], report)
            if report["fixed"]:
                self.fixed[name] = report["fixed"]
            if report["errors"]:
                self.errors[name] = report["errors"]
        return self.shapes[name] or Part.Shape()

    def set_label(self, obj, label):
        obj.Label = label
        if obj.Label != label:
            self.renamed.append((label, obj.Label))

    def piece(self, label, definition_name):
        obj = self.doc.addObject("Part::Feature", "Piece")
        obj.Shape = self.shape(definition_name).copy()
        self.set_label(obj, label)
        obj.addProperty("App::PropertyString", "SketchUp_Definition", "SketchUp", "Définition SketchUp")
        obj.SketchUp_Definition = definition_name
        return obj

    def leaf(self, label, definition_name, path):
        self.where.setdefault(definition_name, " > ".join(path))
        key = (definition_name, label)
        if self.uses[key] == 1:
            return self.piece(label, definition_name)
        # Même définition et même nom : un seul produit STEP, référencé par chaque instance
        # (géométrie écrite une fois, comme dans le .skp).
        if key not in self.shared:
            self.shared[key] = self.piece(label, definition_name)
        obj = self.doc.addObject("App::Link", "Instance")
        obj.LinkedObject = self.shared[key]
        self.set_label(obj, label)
        return obj

    def build(self, node, path=()):
        path = (*path, node["name"])
        children = node["children"]
        if children:
            obj = self.doc.addObject("App::LinkGroup", "Assembly")
            elements = [self.build(child, path) for child in children]
            if self.data["definitions"][node["definition"]]["faces"]:  # géométrie propre à l'assemblage
                elements.append(self.leaf(node["definition"], node["definition"], path))
            obj.ElementList = elements
            self.set_label(obj, node["name"])
        else:
            obj = self.leaf(node["name"], node["definition"], path)
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

    if builder.errors:
        lines = [f"Géométrie à corriger dans SketchUp (tolérance de planéité {PLANAR_TOL} mm) :"]
        for name, errors in builder.errors.items():
            lines.append(f"- définition « {name} » (ex. {builder.where.get(name, '?')}) : "
                         f"{len(errors)} face(s)")
            lines += [f"    face n° {index} : {reason}" for index, reason in errors[:5]]
        print("\n".join("ERREUR " + line for line in lines))
        raise RuntimeError("géométrie à corriger, aucun STEP écrit")

    import Import
    Import.export([model], step_path)
    step_ascii(step_path)

    print("\n".join(tree(model)))
    if builder.renamed:
        print("ATTENTION labels modifiés par FreeCAD :", builder.renamed)
    for name, deviations in builder.fixed.items():
        print(f"NOTE « {name} » : {len(deviations)} face(s) presque plane(s) projetée(s) sur leur plan "
              f"(écart max {max(deviations):.4f} mm <= {PLANAR_TOL} mm)")
    print("STEP :", step_path)
    App.closeDocument(doc.Name)


_previous = DOC_PARAMS.GetBool("DuplicateLabels", False)
DOC_PARAMS.SetBool("DuplicateLabels", True)
try:
    main()
finally:
    DOC_PARAMS.SetBool("DuplicateLabels", _previous)
    sys.stdout.flush()
