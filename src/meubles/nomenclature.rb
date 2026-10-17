# Nomenclature / liste de débit.
#
# Parcourt la hiérarchie : une "pièce" est un groupe ou composant qui ne contient
# plus de groupe ni de composant. Les pièces sont regroupées par définition et
# matériau ; les dimensions (mm) sont celles de la définition, échelle de
# l'instance comprise, triées en Longueur ≥ Largeur ≥ Épaisseur.
require 'csv'

module Meubles
  module Nomenclature
    MM_PER_INCH = 25.4
    HEADERS = ['Repère', 'Pièce', 'Longueur (mm)', 'Largeur (mm)', 'Épaisseur (mm)', 'Quantité',
               'Matériau', 'Surface totale (m²)', 'Sous-ensembles', 'Instances'].freeze

    # roots : entités de départ (sélection, instance de buffet ou model.entities).
    def self.rows(roots)
      acc = {}
      walk(Array(roots).to_a, [], acc)
      acc.values.sort_by { |r| [r[:path].first.to_s, -r[:dims][0], r[:ref]] }
    end

    def self.walk(entities, path, acc)
      entities.each do |e|
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        label = e.name.to_s.empty? ? e.definition.name : e.name
        children = e.definition.entities.select { |c| c.is_a?(Sketchup::Group) || c.is_a?(Sketchup::ComponentInstance) }
        # Un assemblage qui porte aussi sa propre géométrie compte comme une pièce en plus de ses enfants.
        add(acc, e, label, path) if children.empty? || e.definition.entities.grep(Sketchup::Face).any?
        walk(children, path + [label], acc) unless children.empty?
      end
    end

    def self.add(acc, e, label, path)
      dims = dimensions(e)
      ref = e.is_a?(Sketchup::Group) ? label : e.definition.name
      material = e.material ? e.material.display_name : ''
      row = acc[[ref, material, dims]] ||= {
        ref: ref, piece: e.definition.get_attribute('meuble', 'piece') || ref.split(' ').first,
        dims: dims, material: material, qty: 0, instances: [], paths: [], path: path
      }
      row[:qty] += 1
      row[:instances] << label
      row[:qualified] = (row[:qualified] || []) << [path.last, label].compact.join(' > ')
      row[:paths] << path.join(' > ') unless row[:paths].include?(path.join(' > '))
    end

    def self.dimensions(e)
      t = e.transformation
      bb = e.definition.bounds
      scale = [X_AXIS, Y_AXIS, Z_AXIS].map { |axis| axis.transform(t).length.to_f }
      [bb.width, bb.height, bb.depth].zip(scale).map { |len, s| (len.to_f * s * MM_PER_INCH).round(1) }
                                     .sort.reverse
    end

    # Écrit le CSV (séparateur ";", virgule décimale, UTF-8 avec BOM : s'ouvre tel quel dans Excel FR).
    def self.export_csv(roots, path)
      list = rows(roots)
      CSV.open(path, 'w:UTF-8', col_sep: ';') do |csv|
        csv.to_io.write("﻿")
        csv << HEADERS
        list.each do |r|
          l, w, ep = r[:dims]
          csv << [r[:ref], r[:piece], num(l), num(w), num(ep), r[:qty], r[:material],
                  num((l * w * r[:qty] / 1_000_000.0).round(3)), r[:paths].join(' | '), instance_names(r).join(', ')]
        end
        csv << []
        csv << ['TOTAL', nil, nil, nil, nil, list.sum { |r| r[:qty] }, nil,
                num(list.sum { |r| r[:dims][0] * r[:dims][1] * r[:qty] / 1_000_000.0 }.round(3)), nil, nil]
      end
      { path: path, lignes: list.size, pieces: list.sum { |r| r[:qty] } }
    end

    # Noms courts ("Panneau") s'ils sont uniques, sinon préfixés par le parent ("Porte gauche > Panneau").
    def self.instance_names(row)
      names = row[:instances]
      names.uniq.size == names.size ? names : row[:qualified]
    end

    def self.num(value)
      v = value.to_f
      (v == v.round ? v.round.to_s : v.to_s).tr('.', ',')
    end
  end
end
