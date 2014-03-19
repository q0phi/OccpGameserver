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
            token = {:succeed => true}
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
            raise ArgumentError, "Error found in file #{$options[:gamefile]}:#{event.line_num.to_s} - Exec Event: #{new_event.name} does not contain a shell command"
        end
              
        return new_event
    end

    def run(event, app_core)

        Log4r::NDC.push('ExecHandler:')
        
        begin
            # run the provided command
            success = system(event.command, [:out, :err]=>'/dev/null')

        rescue Exception => e
                msg = "Event failed to run: #{e.message}".red
                $log.warn msg
        end
        
        #Log message that the event ran
        msgHash = {:handler => 'ExecHandler', :eventname => event.name, :eventuid => event.eventuid, :custom => event.command }
        
        if( success === true )

            $log.debug "#{event.name} #{event.command} " + "SUCCESS".green
            app_core.INBOX << GMessage.new({:fromid=>'ExecHandler',:signal=>'EVENTLOG', :msg=>msgHash.merge({:status => 'SUCCESS'}) })
            
            #Score Database
            event.scores.each {|score|
                if score[:succeed]
                    app_core.INBOX << GMessage.new({:fromid=>'ExecHandler',:signal=>'SCORE', :msg=>score.merge({:eventuid => event.eventuid})})
                end
            }

        elsif( success === nil )
                msg = "Command failed to run: " + event.command
                $log.error(msg)

        else
            $log.debug "#{event.name} #{event.command} " + "FAILED".red
            app_core.INBOX << GMessage.new({:fromid=>'ExecHandler',:signal=>'EVENTLOG', :msg=>msgHash.merge({:status => 'FAILED'}) })
            
            #Score Database
            event.scores.each {|score|
                if !score[:succeed]
                    app_core.INBOX << GMessage.new({:fromid=>'ExecHandler',:signal=>'SCORE', :msg=>score.merge({:eventuid => event.eventuid})})
                end
            }
        end

        Log4r::NDC.pop

    end

end #end class
end #end module
