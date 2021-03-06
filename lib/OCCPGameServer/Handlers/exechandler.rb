module OCCPGameServer
class ExecHandler < Handler

    def initialize(ev_handler_hash)
        super

    end

    # Parse the exec event xml code into a execevent object
    def parse_event(event, appCore)
        # Perform basic hash conversion
        eh = super
        
        new_event  = ExecEvent.new(eh)
        
        # Check if the :ipaddress field is included
        if eh.include?(:ipaddress)
            # Check if the pool specified exists and has a valid interface
            if !appCore.ipPools.member?(eh[:ipaddress]) 
                raise ArgumentError, "event ip address pool name not valid: #{eh[:ipaddress]}"
            elsif appCore.ipPools[eh[:ipaddress]][:ifname] == nil
                $log.warn "Event #{eh[:name]} uses ip address pool with no interface associated".light_yellow
            end
            # Assign the pool name even if their is no interface ready
            new_event.ipaddress = eh[:ipaddress]
        else
            $log.debug "Event #{eh[:name]} does not define an ip address pool; local exec only"
        end

        # Add scores to event
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

        #Support arbitrary parameter storage
        event.find('parameters/param').each { |param|
            new_event.attributes << { param.attributes["name"] => param.attributes["value"] }
        }
        
        comm = event.find('command').first
        raise ArgumentError, "no executable command defined" if comm == nil 
        commData = comm.content
        raise ArgumentError, "no executable command defined" if commData.empty?

        new_event.command = commData 

        return new_event
    end

    def run(event, app_core)

        Log4r::NDC.push('ExecHandler:')
        
        nsCommand = event.command

        #TODO Optimize command specialization to arrays
        begin
            # run the provided command
            success = system(nsCommand, [:out, :err]=>'/dev/null')
        
        rescue Exception => e
            msg = "Event failed to run: #{e.message}".red
            $log.warn msg
        end
        
        $log.debug "#{event.eventuid.light_magenta} executed #{event.command}"
       
        # Special handling for dry runs
        if $options[:dryrun]
            returnValue = event.attributes.find {|param| param.key?("dryrunstatus") }
            if ( returnValue )        
                case returnValue["dryrunstatus"]
                when 'success'
                    success = true
                when 'fail'
                    success = false
                end
            else
                success = true
            end
        end
 
        returnScores = Array.new 
        status = UNKNOWN
        if( success === true )
            $log.info "#{event.name} #{event.eventuid.light_magenta} " + "SUCCESS".green
            
            #Score Database
            event.scores.each {|score|
                if score[:succeed]
                    returnScores << score
                end
            }

            status = SUCCESS
        elsif( success === nil )
            msg = "Command failed to run: #{event.command}"
            $log.error(msg)

            status = UNKNOWN
        else
            $log.debug "#{event.name} #{event.eventuid.light_magenta} " + "FAILED".light_red
            
            #Score Database
            event.scores.each {|score|
                if !score[:succeed]
                    returnScores << score
                end
            }
            status = FAILURE
        end

        Log4r::NDC.pop
        return {:status => status, :scores => returnScores, :handler => 'ExecHandler', :custom=> event.command}
    end

end #end class
end #end module
