module OCCPGameServer
    class EmailEvent < Event

    attr_accessor :command, :parameters, :ipaddress, :serverip, :serverport,
        :fqdn, :to, :from, :subject, :body

    def initialize(eh)
        super
    end

    def get_command
       
        # Use the Nagios plugin to send the message
        combase = File.join(NAGIOS_PLUGINS_DIR, "check_smtp_send")
        # Generate a Unique message id
        # Forge the sending server to be the same as the from address
        messageid = Time.now.to_i.to_s + '.' + SecureRandom.uuid + '@' + @fqdn

        dateHeader =  "Date: " + Time.now.strftime("%a, %e %b %Y %H:%M:%S %z (%Z)")

        command = "#{combase} -H #{@serverip} -p #{@serverport} --mailto '#{@to}' --mailfrom '#{@from}' --header 'Subject: #{@subject}' --header 'Message-ID: #{messageid}' --header '#{dateHeader}' --body '#{@body}'"

        return command

    end


    end #End Class
end
