class MetasploitHandler < Handler

    attr_accessor :serverhostname, :serverip, :serverport, :servertoken


    def initialize(ev_handler)
        super
        self.serverip = ev_handler[:"server-ip"]
        self.serverport = ev_handler[:"server-port"]
        self.serverhostname = ev_handler[:"server-hostname"]

    end

    def parse_event(event)
        require 'securerandom'

        new_event  = ExecEvent.new
        
        new_event.name = event.find('event-name').first.attributes["name"]
        new_event.eventuid = SecureRandom.uuid

        new_event.starttime = event.find('starttime').first.attributes["time"].to_i
        new_event.endtime = event.find('endtime').first.attributes["time"].to_i
        new_event.frequency = event.find('rate').first.attributes["value"].to_f
        new_event.drift = event.find('drift').first.attributes["value"].to_f

        event.find('score-atomic').each{ |score|
            new_event.scores << { :scoregroup => score.attributes["score-group"],
                                    :value => score.attributes["points"].to_f }
        }

        event.find('parameters/param').each { |param|
            new_event.attributes << { param.attributes["name"] => param.attributes["value"] }
        }

        # puts new_event.name + " " + new_event.eventuid + " " + new_event.attributes.to_s

        return new_event
    end

end #end class
