# Menu Extensions > Meubles.
require_relative 'buffet'
require_relative 'nomenclature'
require_relative 'export_freecad'

module Meubles
  def self.ask_params(title, params)
    keys = Buffet::LABELS.keys
    values = UI.inputbox(keys.map { |k| Buffet::LABELS[k] }, keys.map { |k| params[k].to_s }, title)
    values && keys.zip(values).to_h
  end

  def self.selected_buffet
    model = Sketchup.active_model
    model.selection.find { |e| Buffet.buffet?(e) }
  end

  def self.menu_create
    p = ask_params('Nouveau buffet', Buffet::DEFAULTS)
    Buffet.create(p) if p
  rescue ArgumentError => e
    UI.messagebox(e.message)
  end

  def self.menu_update
    instance = selected_buffet
    return UI.messagebox('Sélectionne un buffet paramétrique.') unless instance
    p = ask_params('Modifier le buffet', Buffet.params_of(instance))
    Buffet.update(instance, p) if p
  rescue ArgumentError => e
    UI.messagebox(e.message)
  end

  def self.menu_export
    model = Sketchup.active_model
    roots = model.selection.empty? ? model.entities : model.selection
    base = model.title.empty? ? 'nomenclature' : "#{model.title}_nomenclature"
    path = UI.savepanel('Exporter la nomenclature', model.path.empty? ? '' : File.dirname(model.path), "#{base}.csv")
    return unless path
    path += '.csv' unless path.downcase.end_with?('.csv')
    result = Nomenclature.export_csv(roots, path)
    UI.messagebox("Nomenclature exportée : #{result[:pieces]} pièces, #{result[:lignes]} repères\n#{path}")
  end

  def self.menu_freecad
    model = Sketchup.active_model
    roots = model.selection.empty? ? model.entities : model.selection
    base = model.title.empty? ? 'modele' : model.title
    path = UI.savepanel('Exporter en STEP', model.path.empty? ? '' : File.dirname(model.path), "#{base}.step")
    return unless path
    result = ExportFreeCAD.to_step(roots, path.sub(/\.(step|stp|json)\z/i, ''))
    UI.messagebox("Export STEP terminé :\n#{result[:step]}\n#{result[:warnings].join("\n")}")
  rescue StandardError => e
    UI.messagebox(e.message)
  end

  def self.menu_freecad_path
    current = ExportFreeCAD.freecad_cmd.to_s
    path =
      if ExportFreeCAD.mac?
        # Le sélecteur de fichiers macOS n'entre pas dans les paquets .app : on saisit le chemin.
        input = UI.inputbox(['Chemin de freecadcmd'],
                            [current.empty? ? '/Applications/FreeCAD.app/Contents/Resources/bin/freecadcmd' : current],
                            'FreeCADCmd')
        input && input[0].strip
      else
        UI.openpanel('FreeCADCmd.exe', File.dirname(current), 'FreeCADCmd|freecadcmd.exe||')
      end
    return unless path && !path.empty?
    return UI.messagebox("Fichier introuvable :\n#{path}") unless File.file?(path)
    Sketchup.write_default(ExportFreeCAD::PREFS, 'freecadcmd', path)
  end

  unless file_loaded?('meubles/main')
    menu = UI.menu('Extensions').add_submenu('Meubles')
    menu.add_item('Nouveau buffet...') { menu_create }
    menu.add_item('Modifier le buffet sélectionné...') { menu_update }
    menu.add_separator
    menu.add_item('Exporter la nomenclature (CSV)...') { menu_export }
    menu.add_item('Exporter en STEP (via FreeCAD)...') { menu_freecad }
    menu.add_item('Chemin de FreeCADCmd...') { menu_freecad_path }
    file_loaded('meubles/main')
  end
end
