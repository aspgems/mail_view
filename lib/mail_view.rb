require 'erb'
require 'tilt'

require 'rack/mime'

class MailView
  autoload :Mapper, 'mail_view/mapper'

  class << self
    def default_email_template_path
      File.expand_path('../mail_view/email.html.erb', __FILE__)
    end

    def default_index_template_path
      File.expand_path('../mail_view/index.html.erb', __FILE__)
    end

    def call(env)
      new.call(env)
    end
  end

  cattr_accessor :viewers, :instance_writer => false, :instance_reader => false

  def self.inherited(base)
    self.viewers ||= []
    self.viewers << base
  end

  def call(env)
    load_viewers

    path_info = env["PATH_INFO"]

    if path_info == "" || path_info == "/"
      links = {}
      MailView.viewers.each do |viewer|
        viewer.actions.inject(links) { |h, action|
          h["#{viewer.name.underscore}.#{action}"] = "#{env["SCRIPT_NAME"]}/#{viewer.name.underscore}/#{action}"
          h
        }
      end

      ok index_template.render(Object.new, :links => links.sort)
    elsif path_info =~ /((?:[\w_]+\/)+)([\w_]+)(\.\w+)?$/
      viewer_name, name, format = $1, $2, ($3 || ".html")
      viewer_klass = viewer_name.split("/").join("/").classify.constantize

      if viewer_klass.actions.include?(name)
        ok render_mail(name, viewer_klass.new.send(name), format)
      else
        not_found
      end
    else
      not_found(true)
    end
  end

  protected
    def load_viewers
      Dir[Rails.root.join('app', 'mailers', '**', '*.rb')].each do |file|
        "#{File.basename(file,'.rb').classify}::Preview".constantize rescue nil
      end
    end

    def self.actions
      public_instance_methods(false).map(&:to_s) - ['call']
    end

    # TODO not used in only one route
    def actions
      public_methods(false).map(&:to_s) - ['call']
    end

    def email_template
      Tilt.new(email_template_path)
    end

    def email_template_path
      self.class.default_email_template_path
    end

    def index_template
      Tilt.new(index_template_path)
    end

    def index_template_path
      self.class.default_index_template_path
    end

  private
    def ok(body)
      [200, {"Content-Type" => "text/html;charset=utf-8"}, [body]]
    end

    def not_found(pass = false)
      if pass
        [404, {"Content-Type" => "text/html", "X-Cascade" => "pass"}, ["Not Found"]]
      else
        [404, {"Content-Type" => "text/html"}, ["Not Found"]]
      end
    end

    def render_mail(name, mail, format = nil)
      body_part = mail

      if mail.multipart?
        content_type = Rack::Mime.mime_type(format)
        body_part = mail.parts.find { |part| part.content_type.match(content_type) } || mail.parts.first
      end

      email_template.render(Object.new, :name => name, :mail => mail, :body_part => body_part)
    end
end
