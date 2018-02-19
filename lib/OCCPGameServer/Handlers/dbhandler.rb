module OCCPGameServer
class DbHandler < Handler

    def initialize(ev_handler_hash)
        super

    end

    # Parse the exec event xml code into a execevent object
    def parse_event(event, appCore)
        # Perform basic hash conversion
        eh = super
        
        new_event  = DbEvent.new(eh)
        
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
            raise ArgumentError, "event ip address pool name not defined"
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

        #Specific entries in the command
        targetServer = event.find('server').first 
        new_event.serverip = targetServer["ipaddress"]
        new_event.serverport = targetServer["port"]
        new_event.dbname = targetServer["dbname"]
        new_event.dbuser = targetServer["username"]
        new_event.dbpass = targetServer["password"]

        event.find('action').each{ |action|
            if action["file"] != nil
                new_event.actions << { file: action["file"] }
            elsif action["sql"] != nil
                new_event.actions << { sql: action["sql"] }
            else
                $log.error "invalid acion statement in #{event.name}".red
                raise ArgumentError, "invalid action statement for sql"
            end
        }
        
        return new_event
    end

    def run(event, app_core)

        if LOG_SHORT_UIDS
            lgeventuid = event.eventuid.split('-').last
        else 
            lgeventuid = event.eventuid
        end
        Log4r::NDC.push("DbHandler-#{lgeventuid}:")
        
        successActions = Array.new
        begin
            
            $log.debug "Beginning DB session to remote server"

            client = Mysql2::Client.new( 
                        :host => event.serverip,
                        :port => event.serverport,
                        :username => event.dbuser,
                        :password => event.dbpass,
                        :database => event.dbname,
                        :flags => Mysql2::Client::MULTI_STATEMENTS,
                        :connect_timeout => 5)

            event.actions.each{ |action|
                # Get the SQL statements from file or directly
                if file = action[:file] 
                    text = File.read(file)
                elsif file = action[:sql]
                    text = action[:sql]
                end
               
                # run the query ignore results
                client.query(text)
                while client.next_result
                end
                $log.debug "#{event.name} executed #{action.to_s}"
                successActions << action
            }
           
            client.close
            $log.debug "Closed DB session to remote server" 
            success = true

        rescue Mysql2::Error => e
            # User failed to login
            success = false
            $log.warn "Event #{event.name} #{lgeventuid} failed to run: #{e.message}".red

        rescue Exception => e
            msg = "Unknown Exception: Event #{event.name} #{lgeventuid} failed to run: #{e.message}".red
            $log.warn msg
            success = false
        end
        
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
            $log.info "#{event.name} " + "SUCCESS".green
            
            #Score Database
            event.scores.each {|score|
                if score[:succeed]
                    returnScores << score
                end
            }

            status = SUCCESS 
        elsif( success === nil )
            msg = "Command failed to run: #{event.name} no points computed : ERROR UNREACHABLE"
            $log.error(msg)

            status = FAILURE 
        else
            $log.info "#{event.name} " + "FAILED".light_red
            successActions.each{ |file, error| $log.debug "#{event.name} #{lgeventuid.light_magenta} " + "PARTIAL SUCCESS ".green + successActions.to_s }
            
            #Score Database
            event.scores.each {|score|
                if !score[:succeed]
                    returnScores << score
                end
            }
            
            status = FAILURE 
        end

        Log4r::NDC.pop
        return {:status => status, :scores => returnScores, :handler => 'DbHandler', :custom=> successActions.to_s}
    end

end #end class
end #end module
