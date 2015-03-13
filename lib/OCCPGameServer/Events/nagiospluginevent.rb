module OCCPGameServer
    class NagiosPluginEvent < Event

    attr_accessor :command, :parameters, :ipaddress

    def initialize(eh)
        super

        raise ArgumentError, "no executable command defined" if eh[:command].nil? || eh[:command].empty?
        
        #Verify that the plugins directory is correctly setup and pre-pend the path
        @command = File.join('/usr/lib/nagios/plugins/', eh[:command])
        

    end

    end #End Class
end
