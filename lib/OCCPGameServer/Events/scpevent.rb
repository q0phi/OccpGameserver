module OCCPGameServer
    class ScpEvent < Event

    attr_accessor :command, :parameters, :ipaddress, :uploads, :downloads,
        :serverip, :serverport, :serveruser, :serverpass

    def initialize(eh)
        super

        @uploads = Array.new
        @downloads = Array.new

    end

    end #End Class
end
