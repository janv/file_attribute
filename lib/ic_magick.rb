# ICMagick &copy; Jan Varwig 2007
#
# http://jan.varwig.org

# ICMagick provides a slim interface to ImageMagick
#
# Contrary to RMagick, ICMagick is merely an interface to call the ImageMagick
# commandline tools in a comfortable way on existing files.
# It can not operate on Bytestreams directly.
module ICMagick
  # Raised when running the ImageMagick command fails.
  class ICMagickException < Exception
  end
  
  # Represents an Image to be processed by ImageMagick
  #
  # To use this, initialize an Image Object using a filename.
  # You can then call methods on that object that correspond to the options
  # available to ImageMagicks convert[http://www.imagemagick.org/script/convert.php]
  # and mogrify[http://www.imagemagick.org/script/mogrify.php] commands.
  # This is implemented through +method_missing+, so validity of called methods
  # isn't verified. Some options are also invalid for either +convert+ or +mogrify+ and
  # should be used only with save or save_as respectively
  #
  # If you're done passing commands to the Image, call either save or save_as to
  # mogrify or convert the image.
  #
  # == Example
  #
  # These statements
  #
  #   image = ICMagick::Image.new "~/original.jpg"
  #   image.resize "#{40}x#{30}"
  #   image.save_as "~/new.jpg"
  #
  # would result in
  #
  #   convert ~/original.jpg -resize "30 x 40" ~/new.jpg
  #
  # being called.
  class Image
    def initialize(filename)
      @filename = filename
      @actions = []
    end

    # Calls +mogrify+
    def save
      Image.run_command("mogrify #{@actions.join(' ')} #{@filename}")
    end
    
    # Calls +convert+
    def save_as(output_filename)
      Image.run_command("convert #{@filename} #{@actions.join(' ')} #{output_filename}")
    end
    
    # Returns the command that +save+ would execute as a string
    def fake_save
      "mogrify #{@actions.join(' ')} #{@filename}"
    end
      
    # Returns the command that +save_as+ would execute as a string
    def fake_save_as(output_filename)
      "convert #{@filename} #{@actions.join(' ')} #{output_filename}"
    end
    
    def method_missing(command, *args) # :nodoc:
      args = args.collect {|a| a.to_s}
      @actions.push("-#{command.to_s.gsub('"','\"')} \"#{args.join(' ').gsub('"','\"')}\"")
    end
    
    # Returns true if the Image object actually refers to an image file
    def is_image?
      Image.is_image? @filename
    end
    
    # Returns a hash containing info about the image file
    #
    # The following keys are defined in the hash:
    #
    # <tt>:format</tt>::  <tt>:jpeg</tt>, <tt>:gif</tt> etc.
    # <tt>:width</tt>::   The width of the image
    # <tt>:height</tt>::  The height of the image
    # 
    # For possible <tt>:format</tt> keys refer to the ImageMagick documentation
    # describing the <tt>identify</tt> command (http://www.imagemagick.org/script/identify.php).
    def info
      output = Image.run_command("identify #{@filename}")
      info_array = output.split      
      return({
        :format => info_array[1].downcase.to_sym,
        :width  => info_array[2].match(/^\d+/)[0].to_i,
        :height => info_array[2].match(/\d+$/)[0].to_i 
      })
      
    end
    
  private

    def self.run_command(command)
      RAILS_DEFAULT_LOGGER.debug "ICMagick running \"#{command}\""
      output = nil
      silence_stream(STDERR) { output = `#{command}` }
      if $? != 0
        raise ICMagickException, "ICMagick command \"#{command}\" failed. Error given: #{$?}"
      else
        return output
      end  
    end
    
    def self.is_image? (filename)
      output = Image.run_command("identify #{filename}")
      if output.empty? then return false
      else                  return true
      end
    rescue ICMagickException
      false
    end

  end  
end