#!/opt/sensu/embedded/bin/ruby
#
# Sensu Handler: sendgrid
#
# This handler formats alerts as mails and sends them off to a pre-defined recipient.
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-handler'
require 'mail'
require 'timeout'

class Sendgrid < Sensu::Handler
  def short_name
    @event['client']['name'] + '/' + @event['check']['name']
  end

  def action_to_string
   @event['action'].eql?('resolve') ? "RESOLVED" : "ALERT"
  end

  def default_config
    #_ Global Settings
    smtp_address = settings['sendgrid']['smtp_address'] || 'smtp.sendgrid.net'
    smtp_port = settings['sendgrid']['smtp_port'] || '587'
    smtp_domain = settings['sendgrid']['smtp_domain'] || 'localhost.localdomain'
    smtp_user = settings['sendgrid']['smtp_user'] || 'yourusername@domain.com'
    smtp_password = settings['sendgrid']['smtp_password'] || 'yourPassword'
    smtp_auth = settings['sendgrid']['smtp_auth'] || 'plain'

    defaults = {
      "mail_from" => settings['sendgrid']['mail_from'] || 'localhost',
      "mail_to" => settings['sendgrid']['mail_to'] || 'root@localhost'
    }

    # Merge per-check configs
    defaults.merge!(@event['check']['sendgrid'] || {})

    params = {
      :mail_to   => defaults['mail_to'],
      :mail_from => defaults['mail_from'],
      :smtp_addr => smtp_address,
      :smtp_port => smtp_port,
      :smtp_domain => smtp_domain,
      :smtp_user => smtp_user,
      :smtp_password => smtp_password,
      :smtp_auth => smtp_auth
    }
  end

  def handle
    params = self.default_config

    body = <<-BODY.gsub(/^ {14}/, '')
            #{@event['check']['output']}
            Host: #{@event['client']['name']}
            Timestamp: #{Time.at(@event['check']['issued'])}
            Address:  #{@event['client']['address']}
            Check Name:  #{@event['check']['name']}
            Command:  #{@event['check']['command']}
            Status:  #{@event['check']['status']}
            Occurrences:  #{@event['occurrences']}
            Environment:  #{@event['client']['environment']}
            Uchiwa Host Link: https://sensu.aerserv.com/#/client/Sensu-localhost/#{@event['client']['name']}
            AWS Host Link: https://console.aws.amazon.com/ec2/v2/home?region=us-east-1#Instances:search=#{@event['client']['name']};sort=instanceType
            Uchiwa Alert Link: https://sensu.aerserv.com/#/client/Sensu-localhost/#{@event['client']['name']}?check=#{@event['check']['name']}
          BODY
    body << "Runbook:  #{@event['check']['runbook']}" if @event['check']['runbook']
    subject = "#{action_to_string} - #{short_name}: #{@event['check']['notification']}"

    Mail.defaults do
      delivery_method :smtp, {
        :address              => params[:smtp_addr],
        :port                 => params[:smtp_port],
        :domain               => params[:smtp_domain],
        :user_name            => params[:smtp_user],
        :password             => params[:smtp_password],
        :enable_starttls_auto => true
      }
    end

    begin
      timeout 10 do
        Mail.deliver do
          to      params[:mail_to]
          from    params[:mail_from]
          subject subject
          body    body
        end

        puts 'sendgrid -- sent alert for ' + short_name + ' to ' + params[:mail_to]
      end
    rescue Timeout::Error
      puts 'sendgrid -- timed out while attempting to ' + @event['action'] + ' an incident -- ' + short_name
    end
  end
end
