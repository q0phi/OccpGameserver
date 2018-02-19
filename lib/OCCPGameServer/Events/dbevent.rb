module OCCPGameServer
    class DbEvent < Event

    attr_accessor :serverip, :serverport, :dbname, :dbuser, :dbpass, :actions

    def initialize(eh)
        super

        @actions = Array.new
    end

    end #End Class
end
