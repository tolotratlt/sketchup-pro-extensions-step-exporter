# Meubles paramétriques + nomenclature - loader
require 'sketchup.rb'
require 'extensions.rb'

module Meubles
  unless file_loaded?(__FILE__)
    ext = SketchupExtension.new('Meubles', File.join(__dir__, 'meubles', 'main'))
    ext.description = 'Parametric buffet, CSV cut list and STEP export via FreeCAD (keeps hierarchy and names).'
    ext.version     = '0.1.0'
    ext.creator     = 'Tolotra'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
