module OCCPGameServer
    class TestEvent < Event

        def initialize(event = {
                :eventuid => '1234567890',
                :eventid => 'global id',
                :name=>'Test Event',
                :handler=>'TestHandler',
                :starttime=> 0,
                :endtime=> 999999,
                :frequency=> 0.0,
                :drift=> 0.0,
                :ipaddress=> 'testnetwork',
            })     
            super
        end

    end
end
