module OCCPGameServer

    class TestHandler < Handler

        def initialize(h = {:name => 'TestHandler'})
            super
        end

        def parse_event(event, appCore)
        
        end

        def run(event, app_core)
            #Stub
            sleep(2)
            return {:status => SUCCESS, :scores => [], :handler => 'TestHandler', :custom=> 'NOOP'}
        end
    end

end
