module OCCPGameServer
class ExecHandler < Handler


    def initialize(ev_handler_hash)
        super
    end

    # Parse the exec event xml code into a execevent object
    def parse_event(event)
        require 'securerandom'

        new_event  = ExecEvent.new

        new_event.eventhandler = event.find("handler").first.attributes["name"]        
        new_event.name = event.find('event-name').first.attributes["name"]
        new_event.eventuid = SecureRandom.uuid
        new_event.starttime = event.find('starttime').first.attributes["time"].to_i
        new_event.endtime = event.find('endtime').first.attributes["time"].to_i
        new_event.freqscale = event.find('rate').first.attributes["scale"].to_s
        new_event.frequency = event.find('rate').first.attributes["value"].to_f
        new_event.drift = event.find('drift').first.attributes["value"].to_f

        event.find('score-atomic').each{ |score|
            token = {}
            if score.attributes["when"] == 'success'
                token = {:succeed => true}
            elsif score.attributes["when"] == 'fail'
                token = {:succeed => false}
            end
            new_event.scores << token.merge( {:scoregroup => score.attributes["score-group"],
                                                :value => score.attributes["points"].to_f } )
        }

        event.find('parameters/param').each { |param|
            new_event.attributes << { param.attributes["name"] => param.attributes["value"] }

        }
        
        program = event.find('command').first
        if not program.nil?
            new_event.command = program.attributes["value"]
        else
            $log.error(event.to_s)
            raise ArgumentError, "Exec Event: #{new_event.name} does not contain a command line parameter"
        end
              
        return new_event
    end

    def run(event, app_core)
        
        begin
            # run the provided command
            success = system(event.command)

        rescue Exception => e
                msg = "Event failed to run: #{e.message}".red
                app_core.INBOX << GMessage.new({:fromid=>'ExecHandler',:signal=>'CONSOLE', :msg=>msg})
        end
        
        if( success === true )
            #record a score
            app_core.INBOX << GMessage.new({:fromid=>'ExecHandler',:signal=>'CONSOLE', :msg=>'RECORD SCORE GOOD'.green})
            event.scores.each {|score|
                if score[:succeed]
                    app_core.INBOX << GMessage.new({:fromid=>'ExecHandler',:signal=>'SCORE', :msg=>score})
                end
            }

        else
            app_core.INBOX << GMessage.new({:fromid=>'ExecHandler',:signal=>'CONSOLE', :msg=>'RECORD SCORE BAD'.red})
            event.scores.each {|score|
                if !score[:succeed]
                    app_core.INBOX << GMessage.new({:fromid=>'ExecHandler',:signal=>'SCORE', :msg=>score})
                end
            }
        end


    end

end #end class
end #end module
