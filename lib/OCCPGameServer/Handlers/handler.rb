module OCCPGameServer

    class Handler

        attr_accessor :name
        
        def initialize(handler_hash)
        
            @name = handler_hash[:name]

        end

        def parse_event(event, appCore)
            require 'securerandom'

            eh = event.attributes.to_h.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
            
            eh.merge!({:eventuid => SecureRandom.uuid})

            return eh
        end

        def run(event, app_core)
            #Stub
        end
    end

end
