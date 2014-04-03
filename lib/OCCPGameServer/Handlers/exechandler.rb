module OCCPGameServer
class ExecHandler < Handler

    @@ipAddress = Struct.new(:ipaddress) do
        def get_address
            if ipaddress == 'random'
                ip = ''
            else
                ip = ipaddress
            end
            return ip
        end
    end

    def initialize(ev_handler_hash)
        super

        @interface = ev_handler_hash[:interface]

    end

    # Parse the exec event xml code into a execevent object
    def parse_event(event)
        require 'securerandom'

        eh = event.attributes.to_h.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
        
        eh.merge!({:eventuid => SecureRandom.uuid})

        new_event  = ExecEvent.new(eh)
        
        event.find('score-atomic').each{ |score|
            
            token = {:succeed => true}
            case score.attributes["when"]
            when 'success'
                token = {:succeed => true}
            when 'fail'
                token = {:succeed => false}
            end
            
            new_event.scores << token.merge( {:scoregroup => score.attributes["score-group"],
                                                :value => score.attributes["points"].to_f } )
        }

        event.find('parameters/param').each { |param|
            new_event.attributes << { param.attributes["name"] => param.attributes["value"] }
        }
        
        return new_event
    end

    def run(event, app_core)

        Log4r::NDC.push('ExecHandler:')
        
        begin
            # run the provided command
            #puts event.name + event.command.to_s
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
                msg = "Command failed to run: #{event.command}"
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
