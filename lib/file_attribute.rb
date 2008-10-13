require 'digest/md5'

# Extension for ActiveRecord to easily attach files to models
#
# Include FileAttribute in the model you want to extend and use has_file
# to configure the attachments.
#
# -- FileAttribute::CONFIG
#
# * <tt>:public_dir</tt>  - Directory for publicly accessible files, usually inside you rails "public" folder
# * <tt>:private_dir</tt> - Directory for private original versions of files
# * <tt>:url_prefix</tt>  - URL-prefix for stored filepaths to make them accessible via Browser
#
# --
# TODO
#
# - CONFIG Klassenspezifisch, nicht mehr global
# - Fehler wenn das Photo schon VOR dem speichern des Datensatzes hochgeladen wird.
#   Dann existiert keine id und der Pfad stimmt nicht
module FileAttribute
  
  CONFIG = { :public_dir  => "#{RAILS_ROOT}/public/photo_data/", 
             :private_dir => "#{RAILS_ROOT}/private/",
             :url_prefix  => "/photo_data/" }
  
  def self.included(model) # :nodoc:
     model.extend  ClassMethods
     model.module_eval do
       before_save :process_files
       after_destroy :destroy_all_files
       validate :validate_files
       private :remove_file, :set_file, :get_file, :process_files, :validate_files
     end
  end
  
  class FilePath # :nodoc:
    # Create a FilePath object from a relative (!) path
    # (relative to the public/private dirs)
    # Alternately a Hash with keys <tt>:path</tt>, <tt>:name</tt>, <tt>:extname</tt>
    # can be used.
    def initialize(path)
      path = "#{path[:path]}/#{path[:name]}#{path[:extname]}" if path.is_a? Hash
      path = Pathname.new(path).cleanpath
      @dirname  = path.dirname
      @fileid   = path.basename.to_s.split('.')[0]
      @extname  = path.extname 
    end
    
    # Der Pfad der unversionierten Datei ohne Präfix
    def unversioned
      version
    end
    
    # alias für unversioned
    def path
      unversioned
    end
    
    # Der Pfad einer versionierten Datei ohne Präfix
    def version(v=nil)
      v = "_#{v}" unless v.blank?
      "#{@dirname}/#{@fileid}#{v}#{@extname}"
    end
    
    # Der öffentliche Pfad einer versionierten Datei
    def public(v=nil)
      Pathname.new("#{FileAttribute::CONFIG[:public_dir]}/#{version(v)}").cleanpath.to_s
    end
    
    # Der private Pfad einer versionierten Datei
    def private(v=nil)
      Pathname.new("#{FileAttribute::CONFIG[:private_dir]}/#{version(v)}").cleanpath.to_s
    end
    
    # Die URL einer versionierten Datei
    def url(v=nil)
      Pathname.new("#{FileAttribute::CONFIG[:url_prefix]}/#{version(v)}").cleanpath.to_s
    end
    
    # Lösche alle Versionen der Datei
    def delete_all
      delete_public
      delete_private
    end
    
    # Kopiert Datei von path in die private-location
    def create_private_from(file)
      file.rewind
      make_private_dir
      File.open(private, 'wb') { |f| f.write(file.read); f.chmod(0664) }
    end
    
    # Kopiert Datei von path in die public-location
    def create_public_from(file)
      file.rewind
      make_public_dir
      File.open(public, 'wb') { |f| f.write(file.read); f.chmod(0664) }
    end
    
  private
    
    # Lösche alle öffentlichen Versionen der Datei
    def delete_public
      FileUtils.rm Dir.glob("#{FileAttribute::CONFIG[:public_dir]}/#{@dirname}/#{@fileid}*")
    end
    
    # Lösche alle privaten Versionen der Datei
    def delete_private
      FileUtils.rm Dir.glob("#{FileAttribute::CONFIG[:private_dir]}/#{@dirname}/#{@fileid}*")
    end
    
    # Erzeuge das private Verzeichnis für die Datei
    def make_private_dir
      FileUtils.mkpath "#{FileAttribute::CONFIG[:private_dir]}/#{@dirname}/"
    end
    
    # Erzeuge das public Verzeichnis für die Datei
    def make_public_dir
      FileUtils.mkpath "#{FileAttribute::CONFIG[:public_dir]}/#{@dirname}/"
    end
    
  end
  
  module ClassMethods
    # Definiert das vorhandensein eines Dateiattributs.
    # 
    # Für ein File-Attribut :attachment muss dabei ein String-Feld
    # attachment_path in der Datenbank-Tabelle vorhanden sein.
    # 
    # FileAttribute stellt anschließend folgende Methoden bereit:
    #
    #  <tt>attachment=(UploadedIO)</tt>:: Speichert eine neue Datei für dieses
    #                                     Attachment, kann in Forms für das
    #                                     File-Field verwendet werden.
    #  <tt>attachment</tt>::              Gibt den Pfad zur Datei für den
    #                                     Browser zurück oder nil falls keine
    #                                     Datei existiert
    #  <tt>remove_attachment=</tt>::      Wenn hier 1, "1" oder true übergeben
    #                                     wird, markiert das die Datei zum
    #                                     löschen
    #  <tt>remove_attachment</tt>::       Immer false, sinn dahinter ist, dass
    #                                     check_boxen mit dem FormBuilder
    #                                     erzeugt werden, die Checkboxen für
    #                                     das entfernen der Datei sollten 
    #                                     dabei immer auf false stehen
    # 
    # == Options for has_file:
    # 
    # <tt>:max_size</tt>:: Maximum filesize in bytes
    # <tt>:versions</tt>:: A Hash describing file versions in the form
    #                      :version => transformation
    #                      where transformation is a Proc with 2 parameters,
    #                      the first being the input file name (the original)
    #                      the second being the output file name (the transformed file).
    #                      
    #                      If :versions are defined, the original file will not
    #                      be placed in the public directory
    # <tt>:public_original</tt>:: true or false. Wether to put the original file
    #                             in the public directory even if versions are defined.
    #                             Defaults to false.
    # 
    # == Example
    # 
    # has_file :picture,
    #   :max_size => 500.kilobytes,
    #   :public_original => true,
    #   :versions => {
    #     :special => lambda { |infile_name, outfile_name| do_stuff(:with => infile_name, :save_to => outfile_name)  }
    #   }
    # 
    # Creates a 'special' version by processing the file. The do_stuff function
    # here is expected to read the infile manipulate it and write the outfile.
    # The browser path for a version can be accessed using +model_instance.attr_name(:version)+,
    # in this case +model_instance.picture(:special)+.
    def has_file(attr_name, options={})
      self.instance_eval do
        (@file_attribute_options ||= {})[attr_name] = options
        # after_save :process_files # TODO: Nur EINMAL beim includen ausführen
        attr_protected "#{attr_name}_path".to_sym
      end
      
      self.class_eval <<-EOF
        def #{attr_name}(version=nil)
          get_file(:#{attr_name}, version)
        end
        
        def #{attr_name}=(file)
          set_file(:#{attr_name}, file)
        end
        
        def remove_#{attr_name}=(b)
          remove_file(:#{attr_name}, b)
        end
        
        def remove_#{attr_name}
          false
        end
      EOF
      # TODO Filter und Validations installieren
    end
    
    
    # Definiert das Vorhandensein eines Dateiattributs mit der besonderheit
    # dass die Datei eine Bilddatei ist.
    # 
    # Stellt gegenüber has_file zusätzlich die <tt>:versions</tt> Option bereit.
    # 
    # Beispiel
    #
    #  has_image :picture, :max_size => 500.kilobytes, :versions => {
    #    :tiny => {:resize => "15x20"}
    #  }
    #
    # Erzeugt neben dem Original eine "tiny" Version die mit dem Resize-Befehl
    # von ImageMagick bearbeitet wurde. Das Schema ist dabei folgendes:
    # :versions ist ein Hash der als Schlüssel die Namen der Versionen und als
    # Werte die ImageMagick-Befehle für diese Versionen enthält.
    # Die Imagemagick-Befehle stehen wieder in einem Hash, mit den Befehlen
    # als Schlüssel und den Befehlsparametern als Werte.
    #
    # Der Browser-Pfad für eine Version wird dabei über
    # 
    #   model_instance.attr_name(:version)
    # 
    # aufgerufen, im obigen Beispiel also ShadowUser.picture(:tiny)
    def has_image(attr_name, options={})
      options.merge!(:image => true)
      has_file(attr_name, options)
    end
  end
  
  def remove_file(attr_name, b) # :nodoc:
    (@remove_files ||= []) << attr_name if b == 1 || b == '1' || b == true
  end
  
  def set_file(attr_name, file) # :nodoc:
    (@set_files ||= {})[attr_name] = file
  end
  
  def get_file(attr_name, version=nil) # :nodoc:
    if self["#{attr_name}_path"].blank?
      return nil
    else
      FilePath.new(self["#{attr_name}_path"]).url(version)
    end
  end
  
  def validate_files # :nodoc:
    (@set_files || {}).each_pair do |attr_name, file|
      break if file.is_a? String
      o = self.class.instance_variable_get(:@file_attribute_options)[attr_name]
      if o[:max_size] && file.size > o[:max_size]
        self.errors.add(attr_name, "file too large")
      end
      
      if o[:image] && !ICMagick::Image.is_image?(file.path)
        self.errors.add(attr_name, "is not an image")
      end
    end
  end
  
  # Die Dateien sollen nicht schon beim verwenden des Accessors bearbeitet
  # werden sondern vor dem Speichern des Models, NACH der Validierung
  # 
  # process files führt diese Speicherung durch
  def process_files # :nodoc:
    #Remove
    (@remove_files || []).each do |file|
      FilePath.new(self["#{file}_path"]).delete_all
      self["#{file}_path"] = nil
    end
    @remove_files = nil
    
    #Set
    (@set_files || {}).each_pair do |attr_name, file|
      break if file.is_a? String
      RAILS_DEFAULT_LOGGER.debug "Setting File #{attr_name} #{file}"
      o = options_for attr_name
      
      path = FilePath.new( :path    => "#{o[:path]}/#{Time.now.strftime('%Y/%m/%d/')}",
                           :name    => Digest::MD5.hexdigest("#{attr_name}#{self.id || self.object_id}#{Time.now}"),
                           :extname => Pathname.new(file.original_filename).extname)
      
      if o[:versions].is_a?(Hash)
        if o[:public_original]
          path.create_private_from file
          original_path = path.private
        else
          path.create_public_from file 
          original_path = path.public
        end
        o[:versions].each_pair do |version, transformation|
          if o[:image] == true && transformation.is_a?(Hash)
            vi = ICMagick::Image.new original_path
            transformation.each_pair { |cmd, params| vi.send(cmd, params) }
            vi.save_as path.public(version)
          elsif transformation.is_a? Proc
            transformation[original_path, path.public(version)]
          end
        end # search version
      else
        path.create_public_from file
      end
      
      # Delete old files and store new
      FilePath.new(self["#{attr_name}_path"]).delete_all unless self["#{attr_name}_path"].blank?
      self["#{attr_name}_path"] = path.unversioned
    end #set_files loop
    @set_files = nil
  end
  
  def destroy_all_files
    self.class.instance_variable_get(:@file_attribute_options).each_pair do |attr_name, options|
      FilePath.new(self["#{attr_name}_path"]).delete_all if self["#{attr_name}_path"]
    end
  end
  
  def options_for(attr_name)
    self.class.instance_variable_get(:@file_attribute_options)[attr_name]
  end

end