module OCCPGameServer
class NagiosPluginHandler < Handler

    @@nagiosStatus = {
        0 => 'OK',
        1 => 'WARNING',
        2 => 'CRITICAL',
        3 => 'UNKNOWN',
    }


    def initialize(ev_handler_hash)
        super

    end

    # Parse the exec event xml code into a execevent object
    def parse_event(event, appCore)
        eh = super

        new_event  = NagiosPluginEvent.new(eh)

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
            token = { }
            case score.attributes["when"]
            when 'OK'
                token = {:status => 0}
            when 'WARNING'
                token = {:status => 1}
            when 'CRITICAL'
                token = {:status => 2}
            when 'UNKNOWN'
                token = {:status => 3}
            end
            new_event.scores << token.merge( {:scoregroup => score.attributes["score-group"],
                                                :value => score.attributes["points"].to_f } )
        }

        #Support arbitrary parameter storage
        event.find('parameters/param').each { |param|
            new_event.attributes << { param.attributes["name"] => param.attributes["value"] }
        }

        # Locate the Nagios command and process it
        comm = event.find('command').first
        raise ArgumentError, "no executable command defined" if comm == nil
        commData = comm.content.strip
        raise ArgumentError, "no executable command defined" if commData.empty?

        commData = File.join(NAGIOS_PLUGINS_DIR, commData)
        raise ArgumentError, "no plugin found installed at #{commData.split[0]}" if not File.file?(commData.split[0])

        new_event.command = commData

        return new_event
    end

    def run(event, app_core)

        Log4r::NDC.push('NagiosPluginHandler:')

        #TODO Optimize command specialization to arrays
        begin

            # run the provided command
            success = system(event.command, [:out, :err]=>'/dev/null')

        rescue Exception => e
            msg = "Event failed to run: #{e.message}".red
            $log.warn msg
        end

        # Special handling for dry runs
        if $options[:dryrun]
            returnValue = event.attributes.detect {|param| param.key?("dryrunstatus") }
            if ( returnValue )
                returnValue = @@nagiosStatus.key(returnValue["dryrunstatus"])
            else
                returnValue = 0
            end
        else
            if $?.nil?
                returnValue = 3
            else
                returnValue = $?.exitstatus
            end
        end
        $log.debug "#{event.eventuid.light_magenta} executed #{event.command}"

        returnScores = Array.new
        status = UNKNOWN

        $log.debug "#{event.eventuid.light_magenta} returned #{returnValue} after executing #{event.command}"

        if( success === nil )
            msg = "Command failed to run: #{event.command}"
            $log.error(msg)
            status = UNKNOWN

        elsif( returnValue === 0 ) #OK

            $log.info "#{event.name} #{event.eventuid.light_magenta} " + @@nagiosStatus[returnValue].green
            status = SUCCESS

        elsif( [1,2,3].include?(returnValue) )

            $log.debug "#{event.name} #{event.eventuid.light_magenta} " + @@nagiosStatus[returnValue].light_red
            status = FAILURE

        else
            $log.error "Nagios plugin horrific failure".light_red
        end

        # Record Scores to Database
        event.scores.each {|score|
            if score[:status] === returnValue
                returnScores << score
            end
        }

        Log4r::NDC.pop
        return {:status => status, :scores => returnScores, :handler => 'NagiosPluginHandler', :custom=> event.command}
    end

end #end class
end #end module
