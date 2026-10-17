# Export STEP : SketchUp -> JSON (hiérarchie + géométrie) -> import_sketchup.py exécuté par FreeCADCmd.
#
# Objectif : la hiérarchie et les noms, rien d'autre (pas de matériaux, textures ni tags).
# Rien n'est renommé ni aplati :
#  - chaque groupe / instance devient un nœud (nom d'instance, nom de définition,
#    matrice locale) avec ses enfants ;
#  - la géométrie (faces planes, boucles extérieures et trous) est stockée une seule
#    fois par définition, dans le repère local de la définition.
# Unités : mm.
require 'json'
require 'open3'

module Meubles
  module ExportFreeCAD
    MM_PER_INCH = 25.4
    FORMAT = 'sketchup-hierarchy'.freeze
    SCRIPT = File.join(__dir__, 'import_sketchup.py').freeze
    PREFS = 'Meubles'.freeze

    # Exporte base.json puis lance FreeCADCmd qui écrit base.step (le JSON intermédiaire est supprimé).
    def self.to_step(roots, base, model: Sketchup.active_model, keep_json: false)
      exe = freecad_cmd
      raise 'FreeCADCmd introuvable (Extensions > Meubles > Chemin de FreeCADCmd...)' unless exe
      json = "#{base}.json"
      step = "#{base}.step"
      File.delete(step) if File.exist?(step)
      export(roots, json, model: model)
      output, status = Open3.capture2e({ 'SU_JSON' => json, 'SU_STEP' => step }, exe, SCRIPT)
      output = output.force_encoding(Encoding::UTF_8).scrub
      raise "FreeCAD a échoué :\n#{output.lines.last(15).join}" unless status.success? && File.exist?(step)
      File.delete(json) unless keep_json
      { step: step, warnings: output.lines.grep(/ATTENTION/).map(&:strip) }
    end

    def self.freecad_cmd
      saved = Sketchup.read_default(PREFS, 'freecadcmd')
      return saved if saved && File.exist?(saved)
      candidates = %w[ProgramFiles ProgramW6432 LOCALAPPDATA].filter_map { |v| ENV[v] }
      candidates.flat_map { |dir| Dir.glob(File.join(dir.tr('\\', '/'), '{Programs/,}FreeCAD*/bin/{freecadcmd,FreeCADCmd}.exe')) }
                .max # version la plus récente par ordre alphabétique
    end

    def self.export(roots, path, model: Sketchup.active_model)
      definitions = {}
      nodes = Array(roots).to_a.select { |e| instance?(e) }.map { |e| node(e, definitions) }
      raise ArgumentError, 'Aucun groupe ni composant à exporter' if nodes.empty?

      data = {
        format: FORMAT, version: 1, units: 'mm',
        source: { file: model.path, title: model.title, sketchup: Sketchup.version },
        definitions: definitions, roots: nodes
      }
      File.write(path, JSON.pretty_generate(data), mode: 'w:UTF-8')
      { path: path, nodes: count(nodes), definitions: definitions.size }
    end

    def self.instance?(e)
      e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
    end

    def self.node(e, definitions)
      d = e.definition
      definitions[d.name] ||= { faces: faces(d) }
      {
        name: e.name.to_s.empty? ? d.name : e.name,
        kind: e.is_a?(Sketchup::Group) ? 'group' : 'component',
        definition: d.name,
        matrix: matrix(e.transformation),
        children: d.entities.select { |c| instance?(c) }.map { |c| node(c, definitions) }
      }
    end

    # Matrice 4x4 en lignes (convention FreeCAD), translation en mm.
    def self.matrix(t)
      a = t.to_a # colonnes SketchUp, translation en pouces
      rows = (0..3).map { |i| (0..3).map { |j| a[j * 4 + i] } }
      (0..2).each { |i| rows[i][3] *= MM_PER_INCH }
      rows.flatten.map { |v| v.round(9) }
    end

    def self.faces(definition)
      definition.entities.grep(Sketchup::Face).map do |f|
        h = { outer: loop_points(f.outer_loop) }
        inner = f.loops.reject(&:outer?).map { |l| loop_points(l) }
        h[:inner] = inner unless inner.empty?
        h
      end
    end

    def self.loop_points(loop)
      loop.vertices.map { |v| v.position.to_a.map { |c| (c * MM_PER_INCH).round(6) } }
    end

    def self.count(nodes)
      nodes.sum { |n| 1 + count(n[:children]) }
    end
  end
end
