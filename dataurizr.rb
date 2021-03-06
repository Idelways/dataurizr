require 'open-uri'
require 'uri'
require 'nokogiri'
require 'base64'

class Dataurizr
  class URICombinator
    def self.combine(relative, to_absolute)
      if relative[0, 7] == "http://"
        relative
      elsif relative[0, 2] == "//"
        # take the schema
        p = URI(to_absolute)
        p.scheme + ":" + relative
      elsif relative[0, 1] == "/"
        p = URI(to_absolute)
        p.path = ''
        p.query = nil
        p.to_s + relative
      else
        p = URI(to_absolute)
        p.path = pop_file_part(p.path)
        p.query = nil
        p.to_s + relative
      end
    end
    
    def self.pop_file_part(path)
      return path if path[-1, 1] == "/"
      
      without_file = path.split('/')
      without_file.pop
      without_file.join('/') + "/"
    end
  end
  
  def initialize(url)
    @url = prefix_url_if_necessary(url)
    
    @doc = Nokogiri::HTML(open(@url), nil, 'UTF-8')
    
    @imgs = []
  end
  
  def to_html
    @doc.to_html
  end
  
  alias to_s to_html
  
  def do_images
    @doc.css('img, input[type=image]').each do |img|
      puts "Bidule #{img[:src]}"
      img[:src] = read_encode_img(img[:src]);
    end
  end
  
  def do_css
    @doc.css('link[rel=stylesheet]').each do |link|
      absolute_url = get_absolute_url(link[:href])
      
      style_tag = @doc.create_element('style')
      
      # add this attribute to distinguich the original style tags from the embeded ones
      style_tag[:"data-embedded"] = "true"
      
      begin
        style_tag.content = cssfile_process(grab_content(absolute_url), absolute_url)
        
        link.after(style_tag)
        link.remove
      end
    end
    
    @doc.css('style:not([data-embedded])').each do |style|
      style.content = cssfile_process(style.content, @url)
    end
  end
  
  def do_javascript
    @doc.css('script').each do |script|
      unless script[:src] == nil
        absolute_url = get_absolute_url(script[:src])
        
        next if absolute_url.nil?
        
        begin
          script_content = grab_content(absolute_url)
          script.remove_attribute("src")
          script.content = "<![CDATA[\n#{script_content}\n]]>"
        end
      end
    end
  end
  
  def do_inline_css
    @doc.css('[style]').each do |element|
      element[:style] = cssfile_process(element[:style], @url)
    end
  end
  
  def do_links
    @doc.css('a[href]').each do |link|
      link[:href] = URICombinator.combine(link[:href], @url)
    end
  end
  
  def available_actions
    self.methods.select{ |e| e.slice(0, 3) == "do_" }
  end
  
  private
    def cssfile_process(file_content, file_path)
      file_content.gsub(%r{url\(["']?(.+?)["']?\)}) { |s| "url(#{read_encode_img($1.strip, file_path)})" }
    end
  
    def grab_content(url)
      # Simple caching
      @cache ||= {}
      
      if @cache.has_key? url
        puts "Cached : #{url}"
        @cache[url]
      else
        puts url
        begin
          return @cache[url] = open(url).read
        rescue OpenURI::HTTPError
          (@notfound ||= []) << url
          puts "404 : #{url}"
          return ""
        rescue OpenSSL::SSL::SSLError
          return ""
        end
      end
    end
    
    def prefix_url_if_necessary(url)
      if url =~ %r{\Ahttps?\://}
        url
      else
        "http://" + url
      end
    end
    
    def encode_url_if_necessary(url)
      # A clever way to detect if the url needs to be encoded. And to avoid double encoding.
      begin
        url.encode("US-ASCII")
        url
      rescue   
        URI.encode(url)
      end
    end
    
    def read_encode_img(uri, to = @url)
      absolute_url = get_absolute_url(uri, to)
      
      img = grab_content(absolute_url)
      
      if img != ""
        "data:image/#{detect_mime_type(uri)};base64,#{Base64.strict_encode64(img)}"
      else
        ""
      end
    end
    
    def get_absolute_url(uri, to = @url)
      # already absolute (with scheme)
      uri = encode_url_if_necessary(uri)
      
      URICombinator.combine(uri, to)
    end
    
    def detect_mime_type(filename)
      filename.split('.').pop.downcase
    end
end