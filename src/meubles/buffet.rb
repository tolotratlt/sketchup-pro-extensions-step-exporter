# Buffet paramétrique : caisson, séparations, étagères, portes en applique.
#
# Les paramètres sont stockés dans le dictionnaire d'attributs "meuble" de la
# définition du buffet. Modifier un paramètre reconstruit une définition dont
# les pièces sont nommées "Type LxlxÉp" : la nomenclature reste toujours juste.
# Longueurs en mm.
module Meubles
  module Buffet
    DICT = 'meuble'.freeze
    # À incrémenter quand la structure générée change : les buffets existants seront reconstruits.
    GENERATOR_VERSION = 2

    DEFAULTS = {
      'largeur' => 1200.0,
      'profondeur' => 450.0,
      'hauteur' => 850.0,
      'compartiments' => 2,
      'etageres_par_compartiment' => 2,
      'epaisseur' => 18.0,
      'epaisseur_dos' => 8.0
    }.freeze

    LABELS = {
      'largeur' => 'Largeur (mm)',
      'profondeur' => 'Profondeur (mm)',
      'hauteur' => 'Hauteur (mm)',
      'compartiments' => 'Compartiments (= portes)',
      'etageres_par_compartiment' => 'Étagères par compartiment',
      'epaisseur' => 'Épaisseur panneaux (mm)',
      'epaisseur_dos' => 'Épaisseur dos (mm)'
    }.freeze

    JOINT_EXT = 2.0   # jeu entre portes et bord du caisson
    JOINT_INT = 3.0   # jeu entre deux portes
    RECUL     = 20.0  # retrait des étagères depuis l'avant
    JEU       = 1.0   # jeu latéral des étagères
    POIGNEE   = [12.0, 25.0, 160.0].freeze # x, y (saillie), z
    POIGNEE_RETRAIT = 40.0

    MATERIAUX = {
      caisson: ['Buffet - Chêne clair', [205, 170, 125]],
      facade: ['Buffet - Laqué blanc', [240, 238, 232]],
      poignee: ['Buffet - Inox brossé', [150, 152, 156]]
    }.freeze

    TAGS = { caisson: 'Buffet - Caisson', etageres: 'Buffet - Étagères', facade: 'Buffet - Façade' }.freeze

    # --- API publique -------------------------------------------------------

    def self.buffet?(entity)
      entity.is_a?(Sketchup::ComponentInstance) && entity.definition.get_attribute(DICT, 'type') == 'buffet'
    end

    def self.params_of(instance)
      DEFAULTS.keys.to_h { |k| [k, instance.definition.get_attribute(DICT, k, DEFAULTS[k])] }
    end

    # Crée un buffet ; position en mm [x, y, z]. Renvoie l'instance.
    def self.create(params = {}, position: [0, 0, 0], name: 'Buffet', model: Sketchup.active_model)
      p = normalize(params)
      operation(model, 'Créer un buffet') do
        origin = Geom::Point3d.new(*position.map { |v| v.to_f.mm })
        instance = model.active_entities.add_instance(definition_for(model, p), Geom::Transformation.new(origin))
        instance.name = name
        instance
      end
    end

    # Modifie les paramètres d'un buffet existant ; seules les clés données changent.
    # Accepte un hash ou des mots-clés : update(b, largeur: 1600) / update(b, { 'largeur' => 1600 }).
    def self.update(instance, changes = {}, model: Sketchup.active_model, **kwargs)
      raise ArgumentError, "L'entité n'est pas un buffet paramétrique" unless buffet?(instance)
      changes = changes.merge(kwargs).transform_keys(&:to_s)
      p = normalize(params_of(instance).merge(changes))
      # Remplacer une définition en cours d'édition fait planter SketchUp : on referme d'abord.
      close_editing(model, instance)
      operation(model, 'Modifier le buffet') do
        old = instance.definition
        instance.definition = definition_for(model, p)
        purge(model, old) unless old == instance.definition
        # Une définition homonyme existait (ancienne version) : SketchUp a suffixé "#1", on rétablit le nom.
        clean = definition_name(p)
        instance.definition.name = clean unless model.definitions[clean]
        instance
      end
    end

    # --- construction -------------------------------------------------------

    def self.normalize(params)
      p = DEFAULTS.merge(params.transform_keys(&:to_s))
      p = p.to_h { |k, v| [k, DEFAULTS[k].is_a?(Integer) ? v.to_i : v.to_f] }
      t = p['epaisseur']
      raise ArgumentError, 'Il faut au moins 1 compartiment' if p['compartiments'] < 1
      raise ArgumentError, "Nombre d'étagères négatif" if p['etageres_par_compartiment'].negative?
      raise ArgumentError, 'Épaisseurs invalides' unless t.positive? && p['epaisseur_dos'].positive?
      if compartment_width(p) < 100
        raise ArgumentError, "Compartiments trop étroits (#{fmt(compartment_width(p))} mm)"
      end
      raise ArgumentError, 'Profondeur trop faible' if p['profondeur'] < p['epaisseur_dos'] + RECUL + 50
      if shelf_spacing(p) < 50
        raise ArgumentError, "Trop d'étagères pour cette hauteur (#{fmt(shelf_spacing(p))} mm entre deux)"
      end
      p
    end

    def self.compartment_width(p)
      n = p['compartiments']
      inner = p['largeur'] - 2 * p['epaisseur']
      (inner - (n - 1) * p['epaisseur']) / n
    end

    def self.shelf_spacing(p)
      k = p['etageres_par_compartiment']
      inner_h = p['hauteur'] - 2 * p['epaisseur']
      (inner_h - k * p['epaisseur']) / (k + 1)
    end

    def self.definition_name(p)
      n = p['compartiments']
      e = n * p['etageres_par_compartiment']
      "Buffet #{n} #{plural(n, 'porte')} #{e} #{plural(e, 'étagère')} " \
        "#{fmt(p['largeur'])}x#{fmt(p['profondeur'])}x#{fmt(p['hauteur'])}"
    end

    def self.definition_for(model, p)
      name = definition_name(p)
      existing = model.definitions[name]
      return existing if existing && params_match?(existing, p)

      d = model.definitions.add(name)
      d.description = "Buffet paramétrique (#{n_label(p)}). Modifier via Extensions > Meubles."
      d.set_attribute(DICT, 'type', 'buffet')
      d.set_attribute(DICT, 'version', GENERATOR_VERSION)
      p.each { |k, v| d.set_attribute(DICT, k, v) }
      build(model, d.entities, p)
      d
    end

    def self.params_match?(definition, p)
      definition.get_attribute(DICT, 'type') == 'buffet' &&
        definition.get_attribute(DICT, 'version') == GENERATOR_VERSION &&
        p.all? { |k, v| definition.get_attribute(DICT, k) == v }
    end

    def self.build(model, ents, p)
      w = p['largeur']
      d = p['profondeur']
      h = p['hauteur']
      t = p['epaisseur']
      tb = p['epaisseur_dos']
      n = p['compartiments']
      k = p['etageres_par_compartiment']
      wi = w - 2 * t
      hi = h - 2 * t
      c = compartment_width(p)

      mat = MATERIAUX.transform_values { |(name, rgb)| material(model, name, rgb) }
      tag = TAGS.transform_values { |name| model.layers[name] || model.layers.add(name) }

      caisson = sub_assembly(ents, 'Caisson')
      place(model, caisson, 'Côté', [t, d, h], 'Côté gauche', [0, 0, 0], tag[:caisson], mat[:caisson])
      place(model, caisson, 'Côté', [t, d, h], 'Côté droit', [w - t, 0, 0], tag[:caisson], mat[:caisson])
      place(model, caisson, 'Plateau', [wi, d, t], 'Bas', [t, 0, 0], tag[:caisson], mat[:caisson])
      place(model, caisson, 'Plateau', [wi, d, t], 'Dessus', [t, 0, h - t], tag[:caisson], mat[:caisson])
      (1...n).each do |i|
        label = n == 2 ? 'Séparation' : "Séparation #{i}"
        place(model, caisson, 'Séparation', [t, d - tb, hi], label,
              [t + i * c + (i - 1) * t, 0, t], tag[:caisson], mat[:caisson])
      end
      place(model, caisson, 'Dos', [wi, tb, hi], 'Dos', [t, d - tb, t], tag[:caisson], mat[:caisson])

      if k.positive?
        etageres = sub_assembly(ents, 'Étagères')
        gap = shelf_spacing(p)
        n.times do |i|
          x = t + i * (c + t) + JEU
          k.times do |j|
            z = t + (j + 1) * gap + j * t
            name = ['Étagère', compartment_label(i, n), level_label(j, k)].reject(&:empty?).join(' ')
            place(model, etageres, 'Étagère', [c - 2 * JEU, d - tb - RECUL, t], name,
                  [x, RECUL, z], tag[:etageres], mat[:caisson])
          end
        end
      end

      facade = sub_assembly(ents, 'Façade')
      dw = (w - 2 * JOINT_EXT - (n - 1) * JOINT_INT) / n
      dh = h - 2 * JOINT_EXT
      px, py, pz = POIGNEE
      n.times do |i|
        x = JOINT_EXT + i * (dw + JOINT_INT)
        # Porte = sous-ensemble (panneau + poignée), origine au coin bas-gauche-avant du panneau.
        porte = sub_assembly(facade, ['Porte', compartment_label(i, n)].reject(&:empty?).join(' '),
                             origin: [x, -t, JOINT_EXT], layer: tag[:facade])
        place(model, porte, 'Panneau de porte', [dw, t, dh], 'Panneau', [0, 0, 0], tag[:facade], mat[:facade])
        handle_right = i <= (n - 1) / 2.0
        hx = handle_right ? dw - POIGNEE_RETRAIT - px : POIGNEE_RETRAIT
        place(model, porte, 'Poignée', [px, py, pz], 'Poignée', [hx, -py, (dh - pz) / 2], tag[:facade], mat[:poignee])
      end
    end

    def self.sub_assembly(ents, name, origin: [0, 0, 0], layer: nil)
      group = ents.add_group
      group.name = name
      group.layer = layer if layer
      group.transformation = Geom::Transformation.new(Geom::Point3d.new(*origin.map { |v| v.to_f.mm }))
      group.entities
    end

    # Une pièce = un composant nommé "Type LxlxÉp" (dimensions triées, en mm),
    # partagé par toutes les pièces identiques du modèle.
    def self.place(model, ents, type, size, name, origin, tag, material)
      instance = ents.add_instance(part(model, type, *size),
                                   Geom::Transformation.new(Geom::Point3d.new(*origin.map { |v| v.to_f.mm })))
      instance.name = name
      instance.layer = tag
      instance.material = material
      instance
    end

    def self.part(model, type, dx, dy, dz)
      name = "#{type} #{[dx, dy, dz].sort.reverse.map { |v| fmt(v) }.join('x')}"
      existing = model.definitions[name]
      if existing && existing.get_attribute(DICT, 'piece') == type &&
         existing.get_attribute(DICT, 'size') == [dx, dy, dz].map { |v| v.round(3) }
        return existing
      end

      d = model.definitions.add(name)
      d.set_attribute(DICT, 'piece', type)
      d.set_attribute(DICT, 'size', [dx, dy, dz].map { |v| v.round(3) })
      pts = [[0, 0], [dx, 0], [dx, dy], [0, dy]].map { |x, y| Geom::Point3d.new(x.mm, y.mm, 0) }
      face = d.entities.add_face(pts)
      face.reverse! if face.normal.z.negative?
      face.pushpull(dz.mm)
      d
    end

    # Supprime une ancienne définition de buffet et ses pièces devenues inutilisées.
    def self.purge(model, definition)
      return if definition.deleted? || definition.count_used_instances.positive?
      parts = nested_definitions(definition).uniq
      model.definitions.remove(definition)
      parts.each do |d|
        model.definitions.remove(d) if !d.deleted? && d.count_used_instances.zero? && d.get_attribute(DICT, 'piece')
      end
    end

    # Sort des contextes d'édition (double-clic) situés dans l'instance ou à l'intérieur.
    def self.close_editing(model, instance)
      path = model.active_path || []
      index = path.index(instance)
      return unless index
      (path.size - index).times { model.close_active }
    end

    def self.nested_definitions(definition)
      definition.entities.flat_map do |e|
        case e
        when Sketchup::Group then nested_definitions(e.definition)
        when Sketchup::ComponentInstance then [e.definition] + nested_definitions(e.definition)
        else []
        end
      end
    end

    # --- utilitaires --------------------------------------------------------

    def self.operation(model, name)
      model.start_operation(name, true)
      result = yield
      model.commit_operation
      result
    rescue StandardError
      model.abort_operation
      raise
    end

    def self.material(model, name, rgb)
      m = model.materials[name]
      return m if m
      m = model.materials.add(name)
      m.color = Sketchup::Color.new(*rgb)
      m
    end

    def self.compartment_label(i, n)
      case n
      when 1 then ''
      when 2 then %w[gauche droite][i]
      when 3 then %w[gauche centre droite][i]
      else "C#{i + 1}"
      end
    end

    def self.level_label(j, k)
      case k
      when 1 then ''
      when 2 then %w[basse haute][j]
      else (j + 1).to_s
      end
    end

    def self.n_label(p)
      "#{p['compartiments']} compartiment(s), #{p['etageres_par_compartiment']} étagère(s) chacun"
    end

    def self.plural(count, word)
      count > 1 ? "#{word}s" : word
    end

    def self.fmt(value)
      v = value.to_f.round(1)
      v == v.to_i ? v.to_i.to_s : v.to_s
    end
  end
end
