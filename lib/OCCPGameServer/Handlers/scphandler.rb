module OCCPGameServer
class ScpHandler < Handler

    def initialize(ev_handler_hash)
        super

    end

    # Parse the exec event xml code into a execevent object
    def parse_event(event, appCore)
        # Perform basic hash conversion
        eh = super
        
        new_event  = ScpEvent.new(eh)
        
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
        new_event.serveruser = targetServer["username"]
        new_event.serverpass = targetServer["password"]

        event.find('upload').each{ |upload|
            new_event.uploads << { source: upload["local"], dest: upload["remote"] }
        }
        event.find('download').each{ |download|
            new_event.downloads << { source: download["remote"], dest: download["local"] }
        }
        
        return new_event
    end

    def run(event, app_core)

        Log4r::NDC.push('ScpHandler:')
        
        begin

            failedMoves = {}
            successMoves = {}
            $log.debug "Beginning SCP session to remote server"
            #success = system(event.command, [:out, :err]=>'/dev/null')
            Net::SCP.start(event.serverip, event.serveruser, {:password => event.serverpass, :number_of_password_prompts => 1,
                                                                :paranoid => false, :timeout=>3}){ |scp|
                event.uploads.each{ |uploadF|
                    begin
                        if File.file?(uploadF[:source])
                            scp.upload! uploadF[:source], uploadF[:dest]
                            successMoves.merge!({uploadF[:source] => nil})
                        end
                    rescue Exception => e
                        failedMoves.merge!({uploadF[:source] => e})
                    end
                }
                event.downloads.each{ |downloadF|
                    begin
                        scp.download! downloadF[:source], downloadF[:dest]
                        successMoves.merge!({downloadF[:source] => nil})
                    rescue Exception => e
                        failedMoves.merge!({downloadF[:source] => e})
                    end
                }
            }
            $log.debug "Closed SCP session to remote server" 
            success = true

        rescue Net::SSH::AuthenticationFailed => e
            # User failed to login
            success = false
            $log.warn "Event failed to run: #{e.message}".red

        rescue Exception => e
            msg = "Event failed to run: #{e.message}".red
            $log.warn msg
        end
        
        $log.debug "#{event.eventuid.light_magenta} executed #{event.command}"
        
        if $options[:dryrun]
            returnValue = event.attributes.find {|param| param.key?("dryrunstatus") }
            if ( returnValue )        
                case returnValue["dryrunstatus"]
                when 'success'
                    success = true
                    failedMoves = {}
                when 'fail'
                    success = false
                end
            else
                success = true
                failedMoves = {}
            end
        end

        returnScores = Array.new
        status = UNKNOWN
        if( success === true and failedMoves.length === 0)

            $log.info "#{event.name} #{event.eventuid.light_magenta} " + "SUCCESS".green
            successMoves.each{ |file, error| $log.debug "#{event.name} #{event.eventuid.light_magenta} " + "SUCCESS ".green + file.to_s }

            status = SUCCESS
            #Score Database
            event.scores.each {|score|
                if score[:succeed]
                    returnScores << score
                end
            }

        elsif( success === nil )
            msg = "Command failed to run: #{event.command}"
            $log.error(msg)
            status = UNKNOWN

        else
            $log.info "#{event.name} #{event.eventuid.light_magenta} " + "FAILED".light_red
            failedMoves.each{ |file, error| $log.debug "#{event.name} #{event.eventuid.light_magenta} " + "FAILED ".light_red + file.to_s + "  " + error.to_s }
            successMoves.each{ |file, error| $log.debug "#{event.name} #{event.eventuid.light_magenta} " + "SUCCESS ".green + file.to_s }
            
            status = FAILURE
            #Score Database
            event.scores.each {|score|
                if !score[:succeed]
                    returnScores << score
                end
            }
        end

        Log4r::NDC.pop
        return {:status => status, :scores => returnScores, :handler => 'ScpHandler', :custom=> successMoves.merge(failedMoves).to_s}
    end

end #end class
end #end module
