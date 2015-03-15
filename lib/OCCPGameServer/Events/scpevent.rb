module OCCPGameServer
    class ScpEvent < Event

    attr_accessor :command, :parameters, :ipaddress, :uploads, :downloads,
        :serverip, :serverport, :serveruser, :serverpass

    def initialize(eh)
        super

        @uploads = Array.new
        @downloads = Array.new

        #raise ArgumentError, "no executable command defined" if eh[:command].nil? || eh[:command].empty?
        @command = eh[:command]
        

    end

    end #End Class
end
