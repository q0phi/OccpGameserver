module OCCPGameServer

    class Handler

        attr_accessor :name
        
        def initialize(handler_hash)
        
            @name = handler_hash[:name]

        end

        def run(event, app_core)
            #Stub
        end
    end

end
