module OCCPGameServer
    class ExecEvent < Event

    attr_accessor :command, :parameters, :ipaddress

    def initialize(eh)
        super

        raise ArgumentError, "no executable command defined" if eh[:command].nil? || eh[:command].empty?
        @command = eh[:command]
        

    end

end #End Class
end
